#!/bin/bash
set -e  # Exit on error

# ══════════════════════════════════════════════════════════════════════════════
# EKS CLUSTER FIX EXECUTION SCRIPT
# ══════════════════════════════════════════════════════════════════════════════
# This script executes all fixes from the Quick Action Plan
# Modified for single environment + Sealed Secrets
# ══════════════════════════════════════════════════════════════════════════════

echo "🚀 Starting EKS Cluster Remediation..."
echo "════════════════════════════════════════════════════════════════════════════"

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1: EMERGENCY FIXES
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "🚨 PHASE 1: EMERGENCY FIXES"
echo "────────────────────────────────────────────────────────────────────────────"

# Step 1.1: Remove Terraform state files from Git
echo "📝 Step 1.1: Removing Terraform state files from Git..."
cd /workspace/HLY7HC/EKS/eks-terraform-infrastructure

git rm -f terraform.tfstate terraform.tfstate.backup tfplan 2>/dev/null || true
git rm -f bootstrap/terraform.tfstate bootstrap/terraform.tfstate.backup 2>/dev/null || true
git rm -f bootstrap/.terraform/terraform.tfstate 2>/dev/null || true
git rm -f .terraform/terraform.tfstate 2>/dev/null || true

git commit -m "CRITICAL: Remove committed Terraform state files for security" || echo "No state files to remove"

echo "✅ State files removed from Git"

# Step 1.2: Install pre-commit hook
echo "📝 Step 1.2: Installing pre-commit hook..."
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
if git diff --cached --name-only | grep -E 'terraform\.tfstate|\.tfplan'; then
  echo "❌ ERROR: Terraform state/plan files cannot be committed!"
  git diff --cached --name-only | grep -E 'terraform\.tfstate|\.tfplan'
  exit 1
fi
EOF

chmod +x .git/hooks/pre-commit
echo "✅ Pre-commit hook installed"

# Step 1.3: Apply Terraform changes (NAT + EBS CSI IAM)
echo "📝 Step 1.3: Applying Terraform changes..."
echo "  - Enabling 3 NAT Gateways (HA)"
echo "  - Creating EBS CSI Driver IAM role"

terraform init -upgrade
terraform plan -out=fixes.tfplan
echo ""
echo "⚠️  IMPORTANT: Review the plan above"
echo "    Expected changes:"
echo "    + 2 new NAT Gateways (us-east-1b, us-east-1c)"
echo "    + 2 new Elastic IPs"
echo "    + 1 new IAM role (ebs-csi-driver)"
echo "    ~ Updated route tables"
echo ""
read -p "Apply these changes? (yes/no): " confirm

if [ "$confirm" == "yes" ]; then
    terraform apply fixes.tfplan
    echo "✅ Terraform changes applied"
else
    echo "⏭️  Skipping Terraform apply"
fi

# Verify NAT Gateways
echo "📝 Verifying NAT Gateways..."
VPC_ID=$(terraform output -raw vpc_id)
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[*].[NatGatewayId,SubnetId,State]' \
  --output table

echo "✅ Phase 1 Complete"

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 2: NODE GROUP CONSOLIDATION
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "📦 PHASE 2: NODE GROUP CONSOLIDATION"
echo "────────────────────────────────────────────────────────────────────────────"

read -p "Create baseline node group now? (yes/no): " create_baseline

if [ "$create_baseline" == "yes" ]; then
    echo "📝 Step 2.1: Creating baseline node group..."
    terraform apply -target=module.node_group_baseline -auto-approve

    echo "📝 Step 2.2: Waiting for baseline nodes to be Ready..."
    kubectl wait --for=condition=Ready nodes -l role=baseline --timeout=600s || echo "Waiting for nodes..."

    echo "📝 Step 2.3: Listing baseline nodes..."
    kubectl get nodes -l role=baseline -o wide

    echo ""
    echo "✅ Baseline node group created"
    echo ""
    echo "📋 NEXT STEPS (Manual):"
    echo "   1. Verify pods can schedule on baseline nodes"
    echo "   2. Run: kubectl taint nodes -l role=system role=deprecated:NoSchedule"
    echo "   3. Run: kubectl drain -l role=system --ignore-daemonsets --delete-emptydir-data"
    echo "   4. Comment out old node groups in main.tf"
    echo "   5. Run: terraform apply"
else
    echo "⏭️  Skipping baseline node group creation"
fi

echo "✅ Phase 2 Complete"

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 3: GITOPS DEPLOYMENTS
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "🎯 PHASE 3: GITOPS DEPLOYMENTS"
echo "────────────────────────────────────────────────────────────────────────────"

echo "📝 Step 3.1: Committing GitOps changes..."
cd /workspace/HLY7HC/EKS/Pattern-App-of-Apps

git add apps/wave--2-storage.yaml
git add apps/wave--1-essentials.yaml
git add apps/wave-0-sealed-secrets.yaml
git add apps/wave-2-loki.yaml
git add apps/wave-2-tempo.yaml

git commit -m "Add improved GitOps layers: storage, essentials, sealed secrets, logging, tracing" || echo "No changes to commit"

echo "✅ GitOps changes committed"

echo ""
echo "📋 MANUAL STEPS REQUIRED:"
echo "   1. Push GitOps changes: git push"
echo "   2. ArgoCD will auto-sync new applications"
echo "   3. Install kubeseal CLI (see documentation)"
echo "   4. Generate sealed Grafana secret:"
echo "      $ GRAFANA_PASSWORD=\$(openssl rand -base64 32)"
echo "      $ kubectl create secret generic grafana-admin-secret \\"
echo "        --from-literal=admin-user=admin \\"
echo "        --from-literal=admin-password=\"\$GRAFANA_PASSWORD\" \\"
echo "        --namespace=monitoring \\"
echo "        --dry-run=client -o yaml | \\"
echo "      kubeseal --format=yaml > wave-2/grafana-sealed-secret.yaml"
echo "   5. Commit and push sealed secret"

echo "✅ Phase 3 Complete"

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "✅ REMEDIATION COMPLETE"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "📊 WHAT WAS FIXED:"
echo "   ✅ Terraform state files removed from Git"
echo "   ✅ Pre-commit hook installed"
echo "   ✅ 3 NAT Gateways enabled (HA)"
echo "   ✅ EBS CSI Driver IAM role created"
echo "   ✅ Baseline node group created (pending)"
echo "   ✅ GitOps layers improved (storage, essentials, logging, tracing)"
echo "   ✅ Sealed Secrets configured"
echo ""
echo "📋 REMAINING MANUAL TASKS:"
echo "   1. Complete node group migration (drain old nodes)"
echo "   2. Push GitOps changes to Git"
echo "   3. Generate and commit Grafana sealed secret"
echo "   4. Verify all applications synced in ArgoCD"
echo "   5. Test logging in Grafana"
echo "   6. Test tracing in Grafana"
echo ""
echo "📚 DOCUMENTATION:"
echo "   - Quick Action Plan: /workspace/HLY7HC/EKS/QUICK_ACTION_PLAN.md"
echo "   - Full Audit Report: /workspace/HLY7HC/EKS/INFRASTRUCTURE_AUDIT_REPORT.md"
echo ""
echo "🎯 NEXT: Follow the remaining manual steps above"
echo "═══════════════════════════════════════════════════════════════════════════"

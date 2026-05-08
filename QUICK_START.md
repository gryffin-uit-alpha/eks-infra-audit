# ⚡ QUICK START - Fix Cluster Now!

**Time:** 60 minutes  
**Skills:** Terraform, kubectl, Git

---

## 🚀 ONE-COMMAND EXECUTION

```bash
cd /workspace/HLY7HC/EKS
./EXECUTE_FIXES.sh
```

Follow the prompts. Script will:
1. Remove state files from Git ✅
2. Enable 3 NAT Gateways ✅
3. Create baseline node group ✅
4. Commit GitOps improvements ✅

---

## 📦 MANUAL STEPS AFTER SCRIPT

### 1. Install kubeseal (5 min)
```bash
# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.25.0/kubeseal-0.25.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.25.0-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/

# macOS
brew install kubeseal
```

### 2. Update EBS CSI with AWS Account ID (2 min)
```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cd Pattern-App-of-Apps
sed -i "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" apps/wave--2-storage.yaml
git add apps/wave--2-storage.yaml
git commit -m "Update EBS CSI with AWS Account ID"
```

### 3. Create Grafana Sealed Secret (5 min)
```bash
cd Pattern-App-of-Apps
./create-grafana-sealed-secret.sh
# ⚠️ SAVE THE PASSWORD IT PRINTS!

git add wave-2/grafana-sealed-secret.yaml
git commit -m "Add Grafana sealed password"
```

### 4. Push All Changes (1 min)
```bash
git push
```

### 5. Wait for ArgoCD Sync (5 min)
```bash
kubectl get applications -n argocd -w
# Wait for all apps to show "Synced" and "Healthy"
```

---

## ✅ VERIFY IT WORKS

### Check Nodes
```bash
kubectl get nodes -o wide
# Expected: 2 baseline nodes (m7i-flex.xlarge)
```

### Check NAT Gateways
```bash
aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$(cd eks-terraform-infrastructure && terraform output -raw vpc_id)" \
  --query 'NatGateways[*].[NatGatewayId,SubnetId,State]' \
  --output table
# Expected: 3 NATs in "available" state
```

### Check Logging
```bash
kubectl get pods -n monitoring -l app=loki
# Expected: loki-0 pod running

# Test log query
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl http://localhost:3100/ready
# Expected: "ready"
```

### Check Tracing
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
# Expected: tempo pod running
```

### Login to Grafana
```bash
# Get the password you saved from create-grafana-sealed-secret.sh
# URL: https://grafana.internal.example.com
# Username: admin
# Password: <the-password-from-script>
```

---

## 🔧 IF SOMETHING FAILS

### Script Failed at Terraform Apply?
```bash
cd eks-terraform-infrastructure
terraform plan
# Review errors
terraform apply
```

### Baseline Nodes Not Ready?
```bash
kubectl get nodes -l role=baseline
kubectl describe node <node-name>
# Check "Conditions" section for errors
```

### ArgoCD App Not Syncing?
```bash
kubectl get application <app-name> -n argocd -o yaml
# Check "status.conditions" for errors

# Force sync
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'
```

### Sealed Secret Won't Decrypt?
```bash
# Check controller
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets -f

# Recreate secret
cd Pattern-App-of-Apps
./create-grafana-sealed-secret.sh
git add wave-2/grafana-sealed-secret.yaml
git commit --amend
git push -f
```

---

## 📊 WHAT YOU GET

| Before | After |
|--------|-------|
| ❌ 6 nodes always on | ✅ 2 nodes baseline |
| ❌ 1 NAT (SPOF) | ✅ 3 NATs (HA) |
| ❌ State in Git | ✅ State secure |
| ❌ Hardcoded secrets | ✅ Sealed Secrets |
| ❌ Only metrics | ✅ Metrics + Logs + Traces |
| 💰 $750/month | 💰 $540/month |

**Savings: $210/month = $2,520/year**

---

## 📚 FULL DOCUMENTATION

- **Execution Details:** `EXECUTION_SUMMARY.md`
- **Full Audit:** `INFRASTRUCTURE_AUDIT_REPORT.md`
- **Architecture Comparison:** `ARCHITECTURE_COMPARISON.md`
- **Detailed Plan:** `QUICK_ACTION_PLAN.md`

---

## 🎯 YOU'RE DONE WHEN...

- [ ] `./EXECUTE_FIXES.sh` completed successfully
- [ ] All GitOps changes pushed to Git
- [ ] Grafana sealed secret created and pushed
- [ ] All ArgoCD apps show "Synced" and "Healthy"
- [ ] Can login to Grafana with sealed password
- [ ] Logs visible in Grafana Explore (datasource: Loki)
- [ ] `kubectl top nodes` shows metrics
- [ ] 3 NAT Gateways in AWS console
- [ ] 2 baseline nodes in `kubectl get nodes`

**Time to completion:** ~60 minutes

**Ready? Go!** → `./EXECUTE_FIXES.sh`

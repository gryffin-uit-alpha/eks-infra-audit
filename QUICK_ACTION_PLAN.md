# ⚡ QUICK ACTION PLAN - EKS Infrastructure Fixes

**Status:** 🔴 NOT PRODUCTION-READY  
**Target:** ✅ Production-Ready in 4 Weeks  
**Current Score:** 65/100 → **Target:** 90/100

---

## 🚨 EMERGENCY ACTIONS (DO IMMEDIATELY)

### 1. Remove State Files from Git ⏱️ 15 min
```bash
cd eks-terraform-infrastructure

# Remove from Git
git rm terraform.tfstate terraform.tfstate.backup tfplan
git rm bootstrap/terraform.tfstate bootstrap/terraform.tfstate.backup
git commit -m "CRITICAL: Remove committed Terraform state files"
git push

# Add pre-commit hook to prevent future commits
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
if git diff --cached --name-only | grep -E 'terraform\.tfstate|\.tfplan'; then
  echo "❌ ERROR: Terraform state/plan files cannot be committed"
  exit 1
fi
EOF
chmod +x .git/hooks/pre-commit
```

**Why:** State files contain sensitive AWS account IDs, VPC IDs, IP addresses. This is a **security breach**.

---

### 2. Rotate Exposed Secrets ⏱️ 10 min
```bash
# Create secret in AWS Secrets Manager
aws secretsmanager create-secret \
  --name /eks/grafana/admin-password \
  --secret-string "$(openssl rand -base64 32)"

# Get the secret (for manual Grafana update)
aws secretsmanager get-secret-value \
  --secret-id /eks/grafana/admin-password \
  --query SecretString \
  --output text
```

**Why:** `REPLACE_WITH_SECURE_PASSWORD` is visible in Git history.

---

## 📅 WEEK 1: CRITICAL BLOCKERS (16 hours)

### Day 1-2: Enable High Availability
**File:** `eks-terraform-infrastructure/main.tf:18`

```hcl
# Change from:
single_nat_gateway = true  # ❌ SPOF

# To:
single_nat_gateway = false  # ✅ 1 NAT per AZ
```

**Apply:**
```bash
cd eks-terraform-infrastructure
terraform plan  # Review: will create 2 additional NAT Gateways
terraform apply
```

⚠️ **Downtime:** 5-10 minutes during NAT Gateway creation  
💰 **Cost:** +$90/month (vs. hours of downtime cost)

---

### Day 3-4: Deploy External Secrets Operator
**Create:** `Pattern-App-of-Apps/apps/wave-0-external-secrets.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://charts.external-secrets.io
    chart: external-secrets
    targetRevision: 0.9.13
    helm:
      values: |
        serviceAccount:
          annotations:
            eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/external-secrets-irsa
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Update:** `wave-3-prometheus-stack.yaml`
```yaml
# Replace hardcoded password with:
grafana:
  admin:
    existingSecret: grafana-admin-secret
    passwordKey: admin-password
```

---

### Day 5: Add IAM Role for External Secrets
**Create:** `eks-terraform-infrastructure/modules/iam/external_secrets.tf`

```hcl
resource "aws_iam_role" "external_secrets" {
  name = "${local.name}-external-secrets-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:external-secrets-system:external-secrets"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "external_secrets" {
  name = "${local.name}-external-secrets-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/eks/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}
```

**Apply:**
```bash
terraform plan
terraform apply
```

---

## 📅 WEEK 2: ENVIRONMENT SEPARATION (24 hours)

### Day 1-3: Create Environment Structure
```bash
cd eks-terraform-infrastructure
mkdir -p environments/{dev,staging,prod}

# Copy current prod config
cp main.tf variables.tf providers.tf backend.tf environments/prod/
```

**Create:** `environments/dev/terraform.tfvars`
```hcl
# Dev environment (cost-optimized)
project_name = "eks-cluster"
environment = "dev"
cluster_name = "eks-dev"
aws_region = "us-east-1"

# Cost savings
single_nat_gateway = true          # Single NAT is OK in dev
availability_zones = ["us-east-1a", "us-east-1b"]  # Only 2 AZs

# Minimal node group
node_group_min_size = 1
node_group_desired_size = 1
node_group_max_size = 3

# Different VPC CIDR to allow VPC peering
vpc_cidr = "10.10.0.0/16"
```

**Create:** `environments/staging/terraform.tfvars`
```hcl
# Staging (prod-like for testing)
project_name = "eks-cluster"
environment = "staging"
cluster_name = "eks-staging"

# Prod-like HA config
single_nat_gateway = false  # 3 NATs
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

vpc_cidr = "10.20.0.0/16"
```

**Create:** `environments/prod/terraform.tfvars`
```hcl
# Production (current config)
project_name = "eks-cluster"
environment = "production"
cluster_name = "eks-production"

single_nat_gateway = false  # Already fixed in Week 1
vpc_cidr = "10.0.0.0/16"
```

---

### Day 4-5: Update Backend Configuration
**Edit:** `environments/prod/backend.tf`
```hcl
terraform {
  backend "s3" {
    bucket = "eks-cluster-hly7hc-us-east-1"
    key    = "prod/terraform.tfstate"  # ✅ Separate state
    region = "us-east-1"
    dynamodb_table = "tfstate-lock"
    encrypt        = true
  }
}
```

**Edit:** `environments/dev/backend.tf`
```hcl
terraform {
  backend "s3" {
    bucket = "eks-cluster-hly7hc-us-east-1"
    key    = "dev/terraform.tfstate"  # ✅ Separate state
    region = "us-east-1"
    dynamodb_table = "tfstate-lock"
    encrypt        = true
  }
}
```

**Deploy Dev Cluster:**
```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

---

## 📅 WEEK 3: OBSERVABILITY STACK (20 hours)

### Day 1-2: Add Loki Stack (Logging)
**Create:** `Pattern-App-of-Apps/apps/wave-2-loki.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: loki-stack
    targetRevision: 2.10.2
    helm:
      values: |
        loki:
          enabled: true
          persistence:
            enabled: true
            size: 50Gi
          config:
            limits_config:
              retention_period: 168h  # 7 days
            compactor:
              retention_enabled: true
        
        promtail:
          enabled: true
          tolerations:
            - effect: NoSchedule
              operator: Exists  # Run on all nodes
        
        grafana:
          enabled: false  # Use existing Grafana
        
        # Node affinity to monitoring nodes
        loki:
          nodeSelector:
            role: monitoring
          tolerations:
            - key: role
              value: monitoring
              effect: NoSchedule
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

### Day 3-4: Add Tempo (Tracing)
**Create:** `Pattern-App-of-Apps/apps/wave-2-tempo.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tempo
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: tempo
    targetRevision: 1.7.2
    helm:
      values: |
        tempo:
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:4317
                http:
                  endpoint: 0.0.0.0:4318
          storage:
            trace:
              backend: s3
              s3:
                bucket: eks-cluster-tempo-traces
                region: us-east-1
        
        persistence:
          enabled: true
          size: 10Gi
        
        serviceAccount:
          annotations:
            eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/tempo-irsa
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

### Day 5: Configure Grafana Datasources
**Create:** `Pattern-App-of-Apps/wave-3/grafana-datasources.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-stack-kube-prom-prometheus:9090
        isDefault: true
      
      - name: Loki
        type: loki
        url: http://loki:3100
      
      - name: Tempo
        type: tempo
        url: http://tempo:3100
```

---

## 📅 WEEK 4: NODE OPTIMIZATION (16 hours)

### Day 1-2: Create Baseline Node Group
**Edit:** `environments/prod/main.tf`

```hcl
# NEW: Single baseline node group
module "node_group_baseline" {
  source = "../../modules/node-group"

  node_group_name              = "baseline"
  create_worker_security_group = true

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = var.cluster_name
  subnet_ids    = module.vpc.private_subnet_ids
  node_role_arn = module.iam.eks_node_role_arn
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr

  cluster_security_group_id = module.eks.cluster_security_group_id

  instance_types = ["m7i-flex.xlarge"]  # 4 vCPU, 16GB
  desired_size   = 2
  min_size       = 2
  max_size       = 4
  disk_size_gb   = 50

  taints = []  # NO taints - accept all workloads

  labels = {
    role     = "baseline"
    workload = "infrastructure"
  }

  local_registry_ip   = module.bastion.private_ip
  local_registry_port = var.local_registry_port

  depends_on = [module.eks, module.bastion]
}

# Remove CoreDNS tolerations (no longer needed)
resource "aws_eks_addon" "coredns" {
  cluster_name = module.eks.cluster_name
  addon_name   = "coredns"
  
  configuration_values = jsonencode({
    tolerations = []  # No taints = no tolerations
    replicaCount = 2
  })

  depends_on = [module.node_group_baseline]
}
```

---

### Day 3-4: Migrate Workloads
**Step 1: Create new baseline nodes**
```bash
cd environments/prod
terraform apply  # Creates node_group_baseline
```

**Step 2: Taint old node groups (prevent new pods)**
```bash
kubectl taint nodes -l role=monitoring role=deprecated:NoSchedule
kubectl taint nodes -l role=application role=deprecated:NoSchedule
```

**Step 3: Drain old nodes (force pod migration)**
```bash
# Monitoring nodes
kubectl get nodes -l role=monitoring -o name | xargs -I {} kubectl drain {} --ignore-daemonsets --delete-emptydir-data

# App nodes
kubectl get nodes -l role=application -o name | xargs -I {} kubectl drain {} --ignore-daemonsets --delete-emptydir-data
```

**Step 4: Verify all pods running on baseline nodes**
```bash
kubectl get pods -A -o wide | grep -v baseline
# Should only show DaemonSets on old nodes
```

---

### Day 5: Remove Old Node Groups
**Edit:** `environments/prod/main.tf`

```hcl
# DELETE these modules:
# module "node_group_monitoring" { ... }
# module "node_group_app" { ... }
```

**Apply:**
```bash
terraform plan  # Should show 2 node groups will be destroyed
terraform apply
```

**Verify cost savings:**
```bash
# Old: 6 nodes × $0.10/hour = $432/month
# New: 2 nodes × $0.10/hour = $144/month
# Savings: $288/month = $3,456/year
```

---

## ✅ VALIDATION CHECKLIST

### Week 1 Completion
- [ ] No `.tfstate` files in Git
- [ ] Pre-commit hook installed
- [ ] 3 NAT Gateways in us-east-1a/b/c
- [ ] External Secrets Operator deployed
- [ ] Grafana password from AWS Secrets Manager
- [ ] All secrets rotated

### Week 2 Completion
- [ ] `environments/dev/` directory exists
- [ ] `environments/staging/` directory exists
- [ ] `environments/prod/` directory exists
- [ ] Each env has separate Terraform state
- [ ] Dev cluster deployed and tested
- [ ] CI/CD updated for multi-env

### Week 3 Completion
- [ ] Loki Stack deployed (wave-2)
- [ ] Tempo deployed (wave-2)
- [ ] Grafana datasources configured
- [ ] Log query working in Grafana
- [ ] Trace query working in Grafana
- [ ] Alertmanager rules updated

### Week 4 Completion
- [ ] Baseline node group created
- [ ] Old node groups drained
- [ ] Old node groups deleted
- [ ] Cost reduced by ~$300/month
- [ ] All pods running on baseline or Karpenter nodes
- [ ] No scheduling errors

---

## 🎯 POST-IMPLEMENTATION TESTS

### Test 1: High Availability
```bash
# Simulate NAT Gateway failure
aws ec2 delete-nat-gateway --nat-gateway-id <NAT-1>

# Verify: Pods in other AZs still healthy
kubectl get pods -A -o wide
```

**Expected:** Only pods in AZ-1 affected, others continue running.

---

### Test 2: Logging Pipeline
```bash
# Generate logs
kubectl run test-pod --image=busybox --restart=Never -- sh -c 'echo "TEST LOG MESSAGE"'

# Query in Grafana Explore
# Datasource: Loki
# Query: {namespace="default"} |= "TEST LOG MESSAGE"
```

**Expected:** Log appears within 10 seconds.

---

### Test 3: Tracing Pipeline
```bash
# Deploy OpenTelemetry demo app
kubectl apply -f https://raw.githubusercontent.com/open-telemetry/opentelemetry-demo/main/kubernetes/opentelemetry-demo.yaml

# Generate traffic
curl http://<frontend-service>/product/1

# View in Grafana Explore
# Datasource: Tempo
```

**Expected:** Distributed trace appears showing all microservice calls.

---

### Test 4: Karpenter Autoscaling
```bash
# Deploy workload requiring 20 vCPUs
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stress-test
spec:
  replicas: 10
  selector:
    matchLabels:
      app: stress
  template:
    metadata:
      labels:
        app: stress
    spec:
      containers:
      - name: stress
        image: polinux/stress
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
EOF

# Watch Karpenter provision new nodes
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

**Expected:** Karpenter provisions 2-3 spot instances within 60 seconds.

---

## 📊 SUCCESS METRICS

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| **Security Score** | 70/100 | 95/100 | ✅ 90+ |
| **HA Score** | 50/100 | 95/100 | ✅ 90+ |
| **Observability Score** | 40/100 | 90/100 | ✅ 90+ |
| **Cost/Month** | $800 | $450 | ✅ <$500 |
| **Terraform Environments** | 1 | 3 | ✅ 3 |
| **NAT Gateways** | 1 | 3 | ✅ 3 |
| **Observability Pillars** | 1/3 | 3/3 | ✅ 3/3 |
| **Static Node Groups** | 3 | 1 | ✅ 1 |

---

## 🚀 GO/NO-GO CRITERIA

### ✅ GO LIVE if:
- [x] All Week 1-4 tasks completed
- [x] All validation tests pass
- [x] Staging environment stable for 7 days
- [x] Rollback plan documented
- [x] On-call team trained on new observability tools

### ❌ NO-GO if:
- [ ] Any `.tfstate` files still in Git
- [ ] Single NAT Gateway in production
- [ ] Hardcoded secrets in manifests
- [ ] Logging or tracing not working
- [ ] No tested rollback plan

---

**Next Steps:** Start Week 1 tasks immediately.  
**Review Date:** End of each week  
**Final Go-Live:** Week 5 (post-implementation testing)

# Role: Lead Platform Engineer & Execution Agent

**Context:** We are going to execute the "Quick Action Plan" to remediate the EKS cluster. However, since this is for learning purposes, I want you to follow the established plan but apply the following specific modifications:

## Modified Constraints:
1. **Single Environment Only:** Skip the "Week 2: Environment Separation" phase entirely. We will not create Dev or Staging environments. Please apply all fixes and deployments directly to our single main cluster.
2. **Secret Management:** Skip AWS Secrets Manager to avoid extra costs. Instead, implement **Bitnami Sealed Secrets** in our GitOps workflow (Wave 0). When you generate the code for this, please include a quick guide on how I should use `kubeseal` to encrypt my Grafana password before committing it to Git.
3. **Compute Optimization:** Please prioritize using AWS Free Tier instances where possible to minimize costs. However, you **are allowed** to use `m7i` and `c7i` instance families for the Baseline Node Group or Karpenter configurations if you determine they are necessary for the cluster's stability and performance.

## Action Request:
Please proceed with the execution of the Quick Action Plan sequentially, keeping these 3 modifications in mind. Start with the immediate emergency fixes and network routing (VPC CIDR / Service CIDR ingress rules), then move into the GitOps/Observability setups. 

Output the exact Terraform code blocks, Kubernetes manifests (ArgoCD yaml), and bash commands needed for the first set of tasks so we can begin fixing the cluster right now.
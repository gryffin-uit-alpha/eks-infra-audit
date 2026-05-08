```
graph TB

%% ===================== AWS MANAGED CONTROL PLANE =====================
subgraph AWS["AWS Cloud (Region)"]

    CP["EKS Control Plane (Managed by AWS)<br/>API Server + Scheduler + Controller Manager"]
    
    OIDC["OIDC Provider (IRSA)"]

    IAM["IAM Roles & Policies<br/>(Node Role, IRSA Roles, Bastion/SSM Role)"]

    SSM["AWS Systems Manager<br/>(Session Manager - No SSH)"]

    %% ===================== STORAGE / DR =====================
    subgraph DR["Disaster Recovery Layer"]
        S3["S3 Bucket<br/>(Velero Backups, Versioning, SSE-KMS)"]
    end

    %% ===================== EVENTING / AUTOSCALING =====================
    subgraph Autoscaling["Autoscaling Control Plane"]
        EventBridge["EventBridge / CloudWatch Events"]
        SQS["SQS Queue (Karpenter Interruption Queue)"]
        EventBridge --> SQS
    end

    %% ===================== VPC =====================
    subgraph VPC["VPC - 10.0.0.0/16"]

        IGW["Internet Gateway"]

        %% ---------------- PUBLIC ----------------
        subgraph Public["Public Subnets (Multi-AZ)"]
            NAT["NAT Gateway (Egress Only)"]
            ALB["Load Balancer (ALB/NLB Ingress)"]
        end

        %% ---------------- PRIVATE ----------------
        subgraph Private["Private Subnets (Multi-AZ)"]

            %% Node groups
            subgraph Nodes["EKS Worker Node Groups"]

                SystemNodes["System Nodes<br/>Taint: system=true:NoSchedule"]
                AppNodes["App Nodes<br/>Taint: app=true:PreferNoSchedule"]
                BatchNodes["Batch / Spot Nodes<br/>Karpenter Managed"]
                IngressNodes["Ingress Controller Nodes"]
                MonitorNodes["Monitoring Nodes<br/>Prometheus/Grafana/Logging"]
            end

            %% Workloads
            subgraph Workloads["Kubernetes Workloads"]
                Apps["Microservices / APIs"]
                System["Core Addons<br/>(CoreDNS, CNI, kube-proxy)"]
                Observability["Observability Stack"]
            end

            %% Karpenter Controller
            Karpenter["Karpenter Controller<br/>(in-cluster controller)"]

            %% Velero
            Velero["Velero Controller<br/>(Backup/Restore)"]

        end
    end
end

%% ===================== CONTROL PLANE CONNECTION =====================
CP -->|"API Calls (Secure Endpoint)"| Nodes
CP -->|"Schedules Pods"| Workloads

%% ===================== NETWORK FLOW =====================
Private -->|"0.0.0.0/0 (Egress)"| NAT
NAT --> IGW

ALB -->|"Ingress Traffic"| Apps

%% ===================== IDENTITY =====================
OIDC -.->|"IRSA: Pod Identity"| S3
OIDC -.->|"IRSA: Pod Identity"| SQS
OIDC -.->|"IRSA: Pod Identity"| AWS

IAM -.->|"Node IAM Role"| Nodes
IAM -.->|"Service Roles"| CP

%% ===================== ACCESS LAYER =====================
SSM ==>|"Secure Access (No SSH)"| SystemNodes

%% ===================== KARPENTER FLOW =====================
Karpenter -->|"Watch Pending Pods"| CP
Karpenter -->|"Provision EC2 via AWS API"| AWS
SQS -->|"Spot interruption events"| Karpenter

%% ===================== BACKUP FLOW =====================
Velero -->|"Backup cluster state"| S3
Velero -->|"Restore workload"| Workloads

%% ===================== OBSERVABILITY =====================
MonitorNodes -->|"Metrics/Logs/Traces"| Observability
Apps -->|"Metrics"| MonitorNodes
SystemNodes -->|"Node metrics"| MonitorNodes

%% ===================== SECURITY BOUNDARY =====================
classDef control fill:#f1f3f5,stroke:#495057;
classDef vpc fill:#e7f5ff,stroke:#1c7ed6;
classDef public fill:#fff4e6,stroke:#f76707;
classDef private fill:#e6fcf5,stroke:#099268;
classDef workload fill:#f8f9fa,stroke:#343a40;

class CP,OIDC,IAM control;
class VPC vpc;
class Public public;
class Private private;
class Apps,System,Observability workload;
```
# --- NEURAL HYPERNOVA: SOVEREIGN INFRASTRUCTURE V1.2.6 ---

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
  backend "s3" {
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "runner_arn" {
  type    = string
  default = ""
}

# --- 1. DATA SOURCES ---
data "aws_caller_identity" "current" {}

data "http" "lb_policy_json" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

# --- 2. NETWORKING ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name = "hypernova-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = "neural-hypernova"
  }
}

# --- 3. EKS CLUSTER (1.31) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = "neural-hypernova"
  cluster_version = "1.31"

  # FORCE Public Visibility
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []
  authentication_mode         = "API_AND_CONFIG_MAP"

  eks_managed_node_groups = {
    brain = {
      instance_types           = ["t3.medium"]
      ami_type                 = "AL2023_x86_64_STANDARD"
      iam_role_name            = "KarpenterNodeRole-neural-hypernova"
      iam_role_use_name_prefix = false
    }
  }

  access_entries = {
    runner = {
      principal_arn = var.runner_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

# --- 4. IAM FOR LOAD BALANCER CONTROLLER (RAW RESOURCES) ---
resource "aws_iam_policy" "lb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lb_policy_json.response_body
}

resource "aws_iam_role" "lb_controller" {
  name = "lb-controller-role-hypernova"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller_attach" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# --- 5. SECURITY ---
resource "aws_security_group_rule" "ray_dash" {
  type              = "ingress"
  from_port         = 8265
  to_port           = 8265
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.node_security_group_id
}

# Webhook Access: Allow the VPC CIDR to hit 9443
# This is more reliable than targeting the Cluster SG ID
resource "aws_security_group_rule" "lbc_webhook_vpc" {
  description       = "Allow VPC (EKS Control Plane) to reach LBC Webhook"
  type              = "ingress"
  from_port         = 9443
  to_port           = 9443
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.eks.node_security_group_id
}

# eBPF Data Plane: Full Node-to-Node
resource "aws_security_group_rule" "node_to_node_all" {
  description              = "Allow all node-to-node traffic for Cilium eBPF"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.eks.node_security_group_id
}

# NLB Health Checks
resource "aws_security_group_rule" "nlb_health_checks" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.eks.node_security_group_id
}

# --- 6. OUTPUTS ---
output "cluster_name" {
  value = module.eks.cluster_name
}
output "region" {
  value = "us-east-1"
}
output "vpc_id" {
  value = module.vpc.vpc_id
}
output "lb_role_arn" {
  value = aws_iam_role.lb_controller.arn
}
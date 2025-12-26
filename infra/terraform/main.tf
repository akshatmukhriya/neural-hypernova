# --- NEURAL HYPERNOVA: SOVEREIGN INFRASTRUCTURE V2.3.1 ---

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

# --- 1. GLOBAL VARIABLES ---
variable "runner_arn" {
  type    = string
  default = ""
}

# --- 2. DATA SOURCES ---
data "aws_caller_identity" "current" {}
data "http" "lb_policy_json" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

# --- 3. NETWORK (VPC) ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"
  name    = "hypernova-vpc"
  cidr    = "10.0.0.0/16"
  azs     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
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

# --- 4. DEDICATED FORGE SECURITY GROUP ---
resource "aws_security_group" "forge_extra" {
  name_prefix = "hypernova-forge-extra-" 
  description = "Bypass rules for Webhooks and eBPF"
  vpc_id      = module.vpc.vpc_id

  # Allow all internal VPC traffic for HostNetwork Webhooks
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Ray Dashboard Public Access
  ingress {
    from_port   = 8265
    to_port     = 8265
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
  tags = { Name = "hypernova-forge-extra-sg" }
}

# --- 5. EKS CLUSTER (1.31) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = "neural-hypernova"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  create_cloudwatch_log_group = false
  authentication_mode         = "API_AND_CONFIG_MAP"
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    brain = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"
      iam_role_name  = "KarpenterNodeRole-neural-hypernova"
      iam_role_use_name_prefix = false
      vpc_security_group_ids   = [aws_security_group.forge_extra.id]
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

# --- 6. IAM FOR LOAD BALANCER CONTROLLER ---
resource "aws_iam_policy" "lb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy-Hypernova"
  policy = data.http.lb_policy_json.response_body
}

resource "aws_iam_role" "lb_controller" {
  name = "lb-controller-role-hypernova"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
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

# --- 7. OUTPUTS ---
output "cluster_name" { value = module.eks.cluster_name }
output "region"       { value = "us-east-1" }
output "vpc_id"       { value = module.vpc.vpc_id }
output "lb_role_arn"  { value = aws_iam_role.lb_controller.arn }
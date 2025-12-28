# --- NEURAL HYPERNOVA: INDUSTRIAL INFRASTRUCTURE V41.0.0 ---

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    http   = { source = "hashicorp/http", version = "~> 3.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
  backend "s3" {
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- 1. GLOBAL IDENTITY & RANDOMIZATION ---
resource "random_string" "id" {
  length  = 6
  special = false
  upper   = false
}

variable "runner_arn" {
  type    = string
  default = ""
}

data "aws_caller_identity" "current" {}

# --- 2. NETWORK FOUNDATION ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name = "hypernova-vpc-${random_string.id.result}"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true 

  # STATIC BEACON: Karpenter will always find these regardless of random_id
  private_subnet_tags = {
    "karpenter.sh/discovery" = "neural-hypernova"
  }
}

# --- 3. DECOUPLED SECURITY (The Shield) ---
resource "aws_security_group" "forge_sg" {
  name        = "hypernova-forge-sg-${random_string.id.result}"
  description = "Linear security group to prevent EKS module circular dependencies"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "VPC Internal Handshake"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "Ray Dashboard NodePort Bypass"
    from_port   = 30265
    to_port     = 30265
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "karpenter.sh/discovery" = "neural-hypernova"
  }
}

# --- 4. THE SOVEREIGN BRAIN (EKS 1.31) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = "hypernova-${random_string.id.result}"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # --- CRITICAL FIX: Bypass Module Encryption Bug ---
  create_kms_key              = false
  create_cloudwatch_log_group = false
  cluster_encryption_config   = {} 

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  # Attach our manual SG to bypass internal module collisions
  create_node_security_group = false
  node_security_group_id     = aws_security_group.forge_sg.id

  eks_managed_node_groups = {
    brain = {
      name           = "brain-pool-${random_string.id.result}"
      instance_types = ["t3.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 1
      max_size       = 1
      desired_size   = 1

      # Force a static IAM role name for the node-join Access Entry
      iam_role_name            = "KarpenterNodeRole-hypernova"
      iam_role_use_name_prefix = false
    }
  }

  # MANDATORY FOR 1.31 JOINING: Trust the Node IAM Role
    access_entries = {
    # 1. Grant the GitHub Runner Admin
    runner = {
      principal_arn = var.runner_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    # 2. Trust the Nodes to join
    nodes = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-hypernova"
      type          = "EC2_LINUX"
    }
    # 3. THE MISSING LINK: Grant the Karpenter CONTROLLER Admin rights
    # Without this, Karpenter is 'deaf' to unschedulable pods.
    karpenter = {
      principal_arn = module.karpenter_controller_role.iam_role_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

# --- 5. KARPENTER CONTROLLER IDENTITY (IRSA) ---
module "karpenter_controller_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.33.0"

  role_name = "karpenter-ctrl-${random_string.id.result}"

  attach_karpenter_controller_policy = true
  karpenter_controller_cluster_name  = "hypernova-${random_string.id.result}"
  
  karpenter_controller_node_iam_role_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-hypernova"
  ]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

# Add description perms so Karpenter can see the cluster
resource "aws_iam_role_policy" "karpenter_discovery" {
  name = "karpenter-discovery-api"
  role = module.karpenter_controller_role.iam_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = ["eks:DescribeCluster", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeInstances", "ec2:DescribeInstanceTypes", "ssm:GetParameter"]
      Effect = "Allow"; Resource = "*"
    }]
  })
}

# --- 6. OUTPUTS ---
output "cluster_name"               { value = module.eks.cluster_name }
output "vpc_id"                     { value = module.vpc.vpc_id }
output "public_subnets"             { value = module.vpc.public_subnets }
output "random_id"                  { value = random_string.id.result }
output "karpenter_controller_role"  { value = module.karpenter_controller_role.iam_role_arn }
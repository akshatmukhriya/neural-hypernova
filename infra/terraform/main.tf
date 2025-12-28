# --- NEURAL HYPERNOVA: INDUSTRIAL INFRASTRUCTURE V50.0.0 ---

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

provider "aws" { region = "us-east-1" }

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

# --- 1. NETWORK ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"
  name    = "hypernova-vpc-${random_string.id.result}"
  cidr    = "10.0.0.0/16"
  azs     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true 

  private_subnet_tags = { "karpenter.sh/discovery" = "neural-hypernova" }
}

# --- 2. THE BRAIN (EKS 1.31) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = "hypernova-${random_string.id.result}"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # --- THE BUG BYPASS ---
  # Every line of encryption/KMS logic is removed to stop the module crash.
  # EKS will default to AWS-managed encryption which is 100% stable.
  create_cloudwatch_log_group = false
  authentication_mode         = "API_AND_CONFIG_MAP"
  
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  node_security_group_additional_rules = {
    ingress_ray = {
      description = "Ray Dashboard NodePort"
      protocol    = "tcp"
      from_port   = 30265
      to_port     = 30265
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_vpc_all = {
      description = "Internal VPC Handshake"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = ["10.0.0.0/16"]
    }
  }

  eks_managed_node_groups = {
    brain = {
      name           = "brain-pool-${random_string.id.result}"
      instance_types = ["t3.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 1
      max_size       = 1
      desired_size   = 1

      iam_role_name            = "KarpenterNodeRole-hypernova"
      iam_role_use_name_prefix = false
    }
  }

  access_entries = {
    nodes = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-hypernova"
      type          = "EC2_LINUX"
    }
  }
}

# --- 3. KARPENTER IAM ---
module "karpenter_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.33.0"
  role_name = "karpenter-ctrl-${random_string.id.result}"
  attach_karpenter_controller_policy = true
  karpenter_controller_cluster_name  = "hypernova-${random_string.id.result}"
  karpenter_controller_node_iam_role_arns = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/KarpenterNodeRole-hypernova"]
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

# --- 4. OUTPUTS (COMPLETE TELEMETRY) ---
output "cluster_name"       { value = module.eks.cluster_name }
output "vpc_id"             { value = module.vpc.vpc_id }
output "public_subnets"     { value = module.vpc.public_subnets }
output "random_id"          { value = random_string.id.result }
output "karpenter_role"     { value = module.karpenter_role.iam_role_arn }
output "cluster_endpoint"   { value = module.eks.cluster_endpoint }
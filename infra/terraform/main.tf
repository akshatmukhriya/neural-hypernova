# --- NEURAL HYPERNOVA: INDUSTRIAL INFRASTRUCTURE V26.0.0 ---

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

# --- 1. GLOBAL VARIABLES ---
variable "runner_arn" {
  type    = string
  default = ""
}

resource "random_string" "id" {
  length  = 4
  special = false
  upper   = false
}

data "aws_caller_identity" "current" {}

# --- 2. NETWORK ---
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
}

# --- 3. DEDICATED SECURITY GROUP (The Forge Shield) ---
resource "aws_security_group" "forge_sg" {
  name_prefix = "hypernova-forge-sg-"
  vpc_id      = module.vpc.vpc_id

  # Rule: Internal Handshake (All ports within VPC)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Rule: Ray Dashboard NodePort (For CLI-NLB Bypass)
  ingress {
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

  lifecycle {
    create_before_destroy = true
  }
}

# --- 4. THE BRAIN (EKS 1.31) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = "hypernova-${random_string.id.result}"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  create_kms_key              = false
  create_cloudwatch_log_group = false
  cluster_encryption_config   = {} 

  authentication_mode            = "API_AND_CONFIG_MAP"
  cluster_endpoint_public_access = true
  
  # IDENTITY: Trust only the creator (Runner)
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    brain = {
      instance_types = ["t3.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      # Attach our custom SG directly to ensure connectivity
      vpc_security_group_ids = [aws_security_group.forge_sg.id]
    }
  }
}

# --- 5. OUTPUTS ---
output "cluster_name"    { value = module.eks.cluster_name }
output "vpc_id"          { value = module.vpc.vpc_id }
output "public_subnets"  { value = module.vpc.public_subnets }
output "random_id"       { value = random_string.id.result }
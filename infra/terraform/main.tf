# --- NEURAL HYPERNOVA: INDUSTRIAL INFRASTRUCTURE V33.0.0 ---

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
  length  = 4
  special = false
  upper   = false
}

variable "runner_arn" {
  type    = string
  default = ""
}

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
  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
}

# --- 2. THE BRAIN (EKS 1.31) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = "hypernova-${random_string.id.result}"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # --- THE ULTIMATE BYPASS: REMOVE ALL OPTIONAL BLOCKS ---
  create_kms_key      = false
  enable_irsa         = true
  authentication_mode = "API_AND_CONFIG_MAP"
  
  # This flag is the single source of truth for admin access
  enable_cluster_creator_admin_permissions = true

  # Security Rules
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
      description = "VPC Internal"
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
    }
  }
}

# --- 3. OUTPUTS ---
output "cluster_name"    { value = module.eks.cluster_name }
output "vpc_id"          { value = module.vpc.vpc_id }
output "public_subnets"  { value = module.vpc.public_subnets }
output "random_id"       { value = random_string.id.result }
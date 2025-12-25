# Standard Provider Config
provider "aws" { region = "us-east-1" }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "hypernova-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # Cost optimization for demo

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { 
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = "neural-hypernova" 
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "neural-hypernova"
  cluster_version = "1.29"
  
  # --- THE FIXES ---
  create_cloudwatch_log_group = false # Script will handle or we just don't need it for demo
  create_kms_key              = false # Use default AWS encryption to save costs/collisions
  cluster_encryption_config   = {}    # Disable custom KMS for the demo to avoid alias conflicts
  # -----------------

  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
  
  enable_cluster_creator_admin_permissions = true
  enable_irsa = true

  eks_managed_node_groups = {
    brain = {
      instance_types = ["t3.medium"]
      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}
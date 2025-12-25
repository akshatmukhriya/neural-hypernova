# Standard Provider Config
provider "aws" { region = "us-east-1" }


resource "aws_security_group_rule" "allow_eks_access" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.cluster_primary_security_group_id
}


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
  cluster_version = "1.31" # Upgraded version

  # --- CONNECTIVITY FIX ---
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  cluster_endpoint_public_access_cidrs     = ["0.0.0.0/0"] # Open for demo; narrow this in production
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    brain = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD" # Modern Linux 2023
      min_size       = 1
      max_size       = 2
      desired_size   = 1
    }
  }
}
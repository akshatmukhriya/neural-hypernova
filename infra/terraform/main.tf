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
  cluster_version = "1.31"

  # --- THE SILENCER ---
  create_cloudwatch_log_group            = false
  cluster_enabled_log_types              = []    # THIS is the missing link. Empty it.
  
  # --- ENCRYPTION BYPASS (Avoids KMS Collision) ---
  create_kms_key                         = false
  cluster_encryption_config              = {} 

  # --- CONNECTIVITY ---
  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = ["0.0.0.0/0"]
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    brain = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"
      
      # This ensures the IAM role has a predictable name for Karpenter
      iam_role_use_name_prefix = false
      iam_role_name            = "KarpenterNodeRole-neural-hypernova"
      
      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
  
  # Add YOUR IAM User to the cluster so you can see resources in the AWS Console
  access_entries = {
    # Replace the ARN with your own IAM ARN (find it in AWS Console -> IAM -> Users)
    admin_user = {
      principal_arn     = "arn:aws:iam::277047392590:root" # Adding the root/account allows you to see it
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks:aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}
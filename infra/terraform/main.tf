# --- NEURAL HYPERNOVA: ARCHITECTURAL DNA V1.2.0 ---

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    http = { source = "hashicorp/http", version = "~> 3.0" }
  }
  backend "s3" {
    # Bucket name injected dynamically by Jockey
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" { region = "us-east-1" }

# --- 1. NETWORK (VPC) ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name    = "hypernova-vpc"
  cidr    = "10.0.0.0/16"
  azs     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true 

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { 
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = "neural-hypernova" 
  }
}

# --- 2. SECURITY (FIREWALLS) ---
resource "aws_security_group_rule" "ray_dashboard" {
  type              = "ingress"
  from_port         = 8265
  to_port           = 8265
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "nlb_health" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.eks.node_security_group_id
}

# --- 3. IDENTITY (IAM) ---
data "http" "lb_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lb_policy.response_body
}

module "lb_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.33.0"
  role_name = "lb-controller-role-hypernova"
  role_policy_arns = { policy = aws_iam_policy.lb_controller.arn }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# --- 4. THE BRAIN (EKS) ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "neural-hypernova"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []
  authentication_mode         = "API_AND_CONFIG_MAP"

  eks_managed_node_groups = {
    brain = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"
      iam_role_name  = "KarpenterNodeRole-neural-hypernova"
      iam_role_use_name_prefix = false
    }
  }

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::277047392590:root"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

# --- OUTPUTS (FOR JOCKEY) ---
output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = "us-east-1" }
output "vpc_id" { value = module.vpc.vpc_id }
output "lb_role_arn" { value = module.lb_role.iam_role_arn }
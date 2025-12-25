# --- NEURAL HYPERNOVA: ARCHITECTURAL DNA ---

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
    # This must match the bucket you created
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- 1. DATA SOURCES & POLICIES (THE BRAIN) ---

# Fetch the official AWS Load Balancer Controller policy
data "http" "lb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

# Declare the IAM Policy (The "Undeclared Resource" Fix)
resource "aws_iam_policy" "lb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "Permissions for EKS Load Balancer Controller"
  policy      = data.http.lb_controller_policy.response_body
}

# --- 2. NETWORK FOUNDATION (VPC) ---

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

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

# --- 3. IDENTITY & ACCESS (IAM ROLES) ---

module "lb_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.33.0"

  role_name = "aws-load-balancer-controller-hypernova"

  role_policy_arns = {
    policy = aws_iam_policy.lb_controller.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# --- 4. THE SOVEREIGN CLUSTER (EKS) ---

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "neural-hypernova"
  cluster_version = "1.31"

  # Cost & Collision Optimization
  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []
  create_kms_key              = false
  cluster_encryption_config   = {} 

  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = ["0.0.0.0/0"]
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    brain = {
      instance_types = ["t3.medium"]
      ami_type       = "AL2023_x86_64_STANDARD"
      
      iam_role_use_name_prefix = false
      iam_role_name            = "KarpenterNodeRole-neural-hypernova"
      
      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }

  authentication_mode = "API_AND_CONFIG_MAP" 

  access_entries = {
    admin_user = {
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

# --- 5. SECURITY ORCHESTRATION ---

resource "aws_security_group_rule" "allow_eks_access" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.cluster_primary_security_group_id
}

resource "aws_security_group_rule" "ray_dashboard_final" {
  type              = "ingress"
  from_port         = 8265
  to_port           = 8265
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.node_security_group_id
}

resource "aws_security_group_rule" "nlb_health_checks" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  security_group_id = module.eks.node_security_group_id
}
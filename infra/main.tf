terraform {
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.23.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "main"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b"]
  private_subnets = ["10.0.0.0/19", "10.0.32.0/19"]
  public_subnets  = ["10.0.64.0/19", "10.0.96.0/19"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet tags are required so AWS Load Balancer Controller can discover
  # where to place internet-facing and internal load balancers.
  public_subnet_tags = {
    "kubernetes.io/cluster/sme" = "shared"
    "kubernetes.io/role/elb"    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/sme"       = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# EKS cluster & managed node group via the official module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "sme" # cluster name
  kubernetes_version = "1.34"

  # Public API endpoint to connect
  # EKS API endpoint is publicly reachable (with auth)
  endpoint_public_access = true
  # Admin permissions in K8s with AWS account
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true # ensure CNI is ready before nodes are marked ready
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  }

  # One managed node group
  eks_managed_node_groups = {
    sme = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 2
      desired_size = 2
    }
  }

  tags = {
    Project = "sme"
  }
}

data "aws_eks_cluster" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name                              = "sme-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    Project = "sme"
  }
}

data "aws_iam_policy_document" "aws_load_balancer_controller_extra" {
  statement {
    sid = "AllowListenerAttributeActions"

    actions = [
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:ModifyListenerAttributes"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "aws_load_balancer_controller_extra" {
  name        = "sme-aws-load-balancer-controller-extra"
  description = "Additional ELBv2 permissions needed by AWS Load Balancer Controller"
  policy      = data.aws_iam_policy_document.aws_load_balancer_controller_extra.json
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_extra" {
  role       = module.aws_load_balancer_controller_irsa_role.iam_role_name
  policy_arn = aws_iam_policy.aws_load_balancer_controller_extra.arn
}

resource "kubernetes_service_account_v1" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.aws_load_balancer_controller_irsa_role.iam_role_arn
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false
  timeout          = 1200
  wait             = true
  cleanup_on_fail  = true

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "false"
    },
    {
      name  = "serviceAccount.name"
      value = kubernetes_service_account_v1.aws_load_balancer_controller.metadata[0].name
    },
    {
      name  = "region"
      value = "eu-central-1"
    },
    {
      name  = "vpcId"
      value = module.vpc.vpc_id
    }
  ]

  depends_on = [
    module.eks,
    module.aws_load_balancer_controller_irsa_role,
    aws_iam_role_policy_attachment.aws_load_balancer_controller_extra,
    kubernetes_service_account_v1.aws_load_balancer_controller
  ]
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

# https certificate? only for option B?
output "cluster_ca_certificate" {
  description = "Base64 CA data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

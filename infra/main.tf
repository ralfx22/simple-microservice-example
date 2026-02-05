terraform {
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.23.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# Use the default VPC of my AWS account and all its subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# EKS cluster & managed node group via the official module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "sme"       # cluster name
  kubernetes_version = "1.34"

  # Public API endpoint to connect
  # EKS API endpoint is publicly reachable (with auth)
  endpoint_public_access                   = true
  # Admin permissions in K8s with AWS account
  enable_cluster_creator_admin_permissions = true

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  addons = {
    vpc-cni = {
      most_recent   = true
      before_compute = true   # ensure CNI is ready before nodes are marked ready
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

# you may have to run terraform apply again to see a value because the provisioning of the load balancer needs time. Only working with option B?
# output "frontend_url" {
#   description = "URL to access the SME frontend"
#   value       = "http://${kubernetes_service_v1.frontend.status[0].load_balancer_ingress[0].hostmame}"
# }

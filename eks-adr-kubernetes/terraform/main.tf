terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.94.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.36"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
  }
}

#---------------------------------------------------------------
# EKS Auth and Providers (for bootstrap)
#---------------------------------------------------------------

provider "aws" {
  region = var.region
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}


variable "name" {}
variable "cluster_name" {}
variable "vpc_cidr" {}
variable "tags" {
  type = map(string)
}

locals {
  name         = var.name
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  tags         = var.tags
}


locals {
  name         = var.variable
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint = local.cluster_name,
    "karpenter.sh/discovery" = local.cluster_name
  }
}

#---------------------------------------------------------------
# VPC Module
#---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

  tags = local.tags
}

#---------------------------------------------------------------
# EKS Cluster Module
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.35"

  cluster_name    = local.cluster_name
  cluster_version = "1.31"
  enable_irsa     = true

  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 7

  eks_managed_node_groups = {
    for idx, subnet in module.vpc.private_subnets :
    "managed-worknode-${idx}" => {
      subnet_ids              = [subnet]
      instance_types          = ["t3a.medium"]
      ebs_optimized           = true
      enable_monitoring       = true
      min_size                = 1
      max_size                = 3
      desired_size            = 1
      node_group_name         = "managed-worknodes-${idx}"
      description             = "EKS managed node group for worknodes (not managed by karpenter)"
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 64
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
      additional_iam_policies = [
        "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
        "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
      ]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# ArgoCD Bootstrap (via Helm Chart)
#---------------------------------------------------------------
resource "helm_release" "argocd" {
  provider   = helm
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.46.8"

  create_namespace = true

  values = [
    file("${path.module}/values/argocd-bootstrap.yaml")
  ]

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "kubectl_config" {
  value = "aws eks --region us-east-1 update-kubeconfig --name ${module.eks.cluster_name}"
}


name        = "develop-infa-services"
eks_name    = "gitops-management-services"
eks_version = "1.31"
region      = "us-east-1"
vpc_cidr    = "10.1.0.0/16"

tags = {
  Blueprint                = "gitops-management-services"
  "karpenter.sh/discovery" = "gitops-management-services"
}

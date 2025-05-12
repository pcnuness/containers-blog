name         = "application-dev-services"
cluster_name = "eks-application-dev-services"
region       = "us-east-1"
vpc_cidr     = "10.1.0.0/16"

tags = {
  Blueprint                 = "eks-application-dev-services"
  "karpenter.sh/discovery" = "eks-application-dev-services"
}

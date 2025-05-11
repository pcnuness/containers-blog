name         = "application-poc-services"
cluster_name = "eks-application-poc-services"
region       = "us-east-1"
vpc_cidr     = "10.1.0.0/16"

tags = {
  Blueprint                 = "eks-application-poc-services"
  "karpenter.sh/discovery" = "eks-application-poc-services"
}

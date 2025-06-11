name         = "infa-ops-services"
cluster_name = "eks-infa-ops-services"
eks_version  = "1.31"
region       = "us-east-1"
vpc_cidr     = "10.1.0.0/16"

tags = {
  Blueprint                 = "eks-infa-ops-services"
  "karpenter.sh/discovery" = "eks-infa-ops-services"
}

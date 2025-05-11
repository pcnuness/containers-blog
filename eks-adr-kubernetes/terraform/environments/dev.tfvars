name         = "eks-dev-cluster"
region       = "us-east-1"
vpc_cidr     = "10.1.0.0/16"

tags = {
  Blueprint                 = "eks-dev-cluster"
  "karpenter.sh/discovery" = "eks-dev-cluster"
}

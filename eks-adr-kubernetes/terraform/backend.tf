/*
terraform {
  backend "s3" {}
}
*/

# EXEC LOCAL
terraform {
  backend "s3" {
    bucket         = "730335564649-backend-iac-opentofu"
    key            = "pcnuness/containers-blog/eks-adr-kubernetes/cluster-kubernetes/terraform.tfstate"
    region         = "us-east-1"
  }
}

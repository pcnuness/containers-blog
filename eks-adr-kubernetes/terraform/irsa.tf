#---------------------------------------------------------------
# ALB
#---------------------------------------------------------------

module "irsa_aws_lb_controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name                              = "cpe-${local.cluster_name}-aws-load-balancer-controller-irsa"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller-sa"]
    }
  }

  role_policy_arns = {
    ElasticLoadBalancingReadOnly = "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly"
  }

  tags = local.tags

}

#---------------------------------------------------------------
# VPC CNI - AWS-NODES
#---------------------------------------------------------------

module "vpc_cni_ipv4_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name                      = "cpe-${local.cluster_name}-vpc-cni-ipv4-irsa"
  attach_vpc_cni_policy          = true
  vpc_cni_enable_ipv4            = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# NODE AUTOSCALER
#---------------------------------------------------------------

module "karpenter_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name                          = "cpe-${local.cluster_name}-karpenter-controller-irsa"
  attach_karpenter_controller_policy = true

  karpenter_controller_cluster_name       = module.eks.cluster_name
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["managed-worknode-0"].iam_role_arn
  ]


  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }

  role_policy_arns = {
    fluentbit = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}


#---------------------------------------------------------------
# SECRETS MANAGER
#---------------------------------------------------------------

module "irsa_secrets_store_provider_aws" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name                                           = "cpe-${local.cluster_name}-secrets-store-csi-driver-irsa"
  attach_external_secrets_policy                      = true
  external_secrets_ssm_parameter_arns                 = ["arn:aws:ssm:*:*:parameter/paul"]
  external_secrets_secrets_manager_arns               = ["arn:aws:secretsmanager:*:*:secret:paul"]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:secrets-store-csi-driver"]
    }
  }

  tags = local.tags
}

module "irsa_external_secrets" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name                          = "cpe-${local.cluster_name}-external-secrets-irsa"
  attach_external_secrets_policy     = true

  # Exemplos com escopos de acesso - ajuste conforme sua organização
  external_secrets_ssm_parameter_arns   = ["arn:aws:ssm:*:*:parameter/*"]
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:*:*:secret:*"]
  external_secrets_kms_key_arns         = ["arn:aws:kms:*:*:key/*"]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-secrets"]
    }
  }

  tags = local.tags
}


#---------------------------------------------------------------
# EBS & EFS
#---------------------------------------------------------------

module "irsa_ebs_csi_driver" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name             = "cpe-${local.cluster_name}-ebs-csi-controller-irsa"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "irsa_efs_csi_driver" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name             = "cpe-${local.cluster_name}-efs-csi-controller-irsa"
  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "velero_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name             = "cpe-${local.cluster_name}-velero-irsa"
  attach_velero_policy  = true
  velero_s3_bucket_arns = ["arn:aws:s3:::velero-backups"]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["velero:velero"]
    }
  }

  tags = local.tags
}

#---------------------------------------------------------------
# LOGS
#---------------------------------------------------------------

resource "aws_iam_policy" "fluentbit" {
  name        = "cpe-${local.cluster_name}-fluentbit-irsa"
  description = "Permissions for Fluent Bit to write logs to CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",
          "logs:CreateLogGroup"
        ],
        Resource = "*"
      }
    ]
  })
}

module "irsa_fluentbit" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name                       = "cpe-${local.cluster_name}-fluentbit-irsa"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:fluentbit"]
    }
  }

  role_policy_arns = {
    fluentbit = aws_iam_policy.fluentbit.arn
  }

  tags = local.tags
}

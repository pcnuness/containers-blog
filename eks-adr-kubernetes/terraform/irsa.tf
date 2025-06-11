# ==================================================================
# MODULE - KARPENTER - AWS EKS
# ==================================================================
 
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.35"
 
  cluster_name                    = local.cluster_name
  enable_v1_permissions           = true
  iam_role_use_name_prefix        = false
  iam_role_name                   = "${local.cluster_name}-karpenter-controller-irsa"
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "${local.cluster_name}-karpenter-node-irsa"
  enable_pod_identity             = true
  create_pod_identity_association = true
  namespace                       = "karpenter"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

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
      provider_arn               = local.aws_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  role_policy_arns = {
    ElasticLoadBalancingReadOnly = "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly"
  }

  tags = local.tags

}

module "external_dns_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                     = "cpe-${local.cluster_name}-external-dns-irsa"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/767397938339.realhandsonlabs.net"]

  oidc_providers = {
    ex = {
      provider_arn               = local.aws_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
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
      provider_arn               = local.aws_eks.oidc_provider_arn
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
      provider_arn               = local.aws_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-secrets"]
    }
  }

  tags = local.tags
}


#---------------------------------------------------------------
# EBS & EFS
#---------------------------------------------------------------

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.54"

  role_name             = "${local.cluster_name}-aws-ebs-csi-driver-irsa"
  role_description      = "EKS IRSA for AWS EBS CSI Driver in ${local.cluster_name} cluster"
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = local.aws_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "irsa_efs_csi_driver" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30.0"

  role_name             = "cpe-${local.cluster_name}-efs-csi-controller-irsa"
  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = local.aws_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
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
      provider_arn               = local.aws_eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:fluentbit"]
    }
  }

  role_policy_arns = {
    fluentbit = aws_iam_policy.fluentbit.arn
  }

  tags = local.tags
}

# ==================================================================
# MODULE - AWS IAM - EKS IRSA ADOT
# ==================================================================

module "adot_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.54"

  role_name        = "${local.cluster_name}-adot-collector-irsa"
  role_description = "EKS IRSA for ADOT Collector in ${local.cluster_name} cluster"
  role_policy_arns = {
    prometheus = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
    xray       = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
    cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
  oidc_providers = {
    main = {
      provider_arn               = local.aws_eks.oidc_provider_arn
      namespace_service_accounts = ["opentelemetry:adot-collector-sa"]
    }
  }
}
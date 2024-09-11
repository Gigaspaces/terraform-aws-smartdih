locals {
  account_id   = data.aws_caller_identity.current.account_id
  cluster_name = coalesce(var.cluster_name, "${var.name}-dih")
  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
      configuration_values = jsonencode({
        controller = {
          extraVolumeTags = var.tags
        }
      })
    }
  }
  worker_node_additional_configs = {
    worker = {
      iam_role_additional_policies = {
        "cluster-node-policy" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name}-cluster-node-policy"
        "ssm-policy"          = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
      labels = merge({ Name = "${var.name}-worker" }, var.tags)
      tags   = merge({ Name = "${var.name}-worker" }, var.tags)
    }
    ingress = {
      iam_role_additional_policies = {
        "cluster-node-policy" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name}-cluster-node-policy"
        "ssm-policy"          = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
      labels = merge({ Name = "${var.name}-ingress" }, var.tags)
      tags   = merge({ Name = "${var.name}-ingress" }, var.tags)
    }
    generic = {
      iam_role_additional_policies = {
        "cluster-node-policy" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.name}-cluster-node-policy"
        "ssm-policy"          = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
      labels = merge({ Name = "${var.name}-generic" }, var.tags)
      tags   = merge({ Name = "${var.name}-generic" }, var.tags)
    }
  }
}

# #####################################
# # Managed node groups deep merge
# #####################################
data "utils_deep_merge_yaml" "merged_node_groups_configs" {
  input = [for k, v in {
    default : var.default_managed_node_groups
    managed : var.managed_node_groups,
    local : local.worker_node_additional_configs
  } : yamlencode(v)]

  deep_copy_list = false
  append_list    = false
}

#####################################
# KMS
#####################################
module "kms" {
  count   = var.kms_enable == true ? 1 : 0
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 1.5"

  aliases               = ["eks/${var.name}"]
  description           = "${var.name} cluster encryption key"
  enable_default_policy = true
  key_owners            = [data.aws_caller_identity.current.arn]

  tags = var.tags
}

#####################################
# EKS
#####################################
module "k8s" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.16.0"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_version
  cluster_addons  = merge(var.cluster_addons, local.cluster_addons)

  tags                            = local.tags
  vpc_id                          = coalesce(var.vpc_id, try(module.vpc[0].vpc_id, null))
  subnet_ids                      = coalesce(var.private_subnet_ids, try(module.vpc[0].private_subnets, null))
  control_plane_subnet_ids        = coalesce(var.private_subnet_ids, try(module.vpc[0].private_subnets, null))
  eks_managed_node_group_defaults = var.eks_managed_node_group_defaults

  eks_managed_node_groups   = yamldecode(data.utils_deep_merge_yaml.merged_node_groups_configs.output)
  aws_auth_accounts         = [local.account_id]
  manage_aws_auth_configmap = var.manage_aws_auth_configmap
  create_aws_auth_configmap = var.create_aws_auth_configmap

  node_security_group_additional_rules = var.node_security_group_additional_rules
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.k8s_whitelist_cidrs

  aws_auth_roles = var.aws_auth_roles != null ? var.aws_auth_roles : [
    {
      username = "Administrator-Role"
      rolearn  = "arn:aws:iam::${local.account_id}:role/Administrator-Role"
      groups   = ["system:masters", "system:bootstrappers", "system:nodes"]
    },
    {
      username : var.noc_role_name
      rolearn : "arn:aws:iam::${local.account_id}:role/${var.noc_role_name}"
      groups : ["system:masters", "system:bootstrappers", "system:nodes"]
    },
    {
      username : "sso_admin"
      rolearn : "arn:aws:iam::${local.account_id}:role/AWSReservedSSO_AdministratorAccess_65ce56cdfa5909df"
      groups : ["system:masters", "system:bootstrappers", "system:nodes"]
    },
    {
      username : "sso_power_user"
      rolearn : "arn:aws:iam::${local.account_id}:role/AWSReservedSSO_PaaS-PowerUserAccess_585a8d31fc64353b"
      groups : ["system:masters", "system:bootstrappers", "system:nodes"]
    }
  ]



  # External encryption key
  #   create_kms_key = var.kms_enable && var.create_kms_key ? true : false
  #   cluster_encryption_config = var.kms_enable && var.create_kms_key ? {
  #     resources        = ["secrets"]
  #     provider_key_arn = module.kms.key_arn
  #   } : {}

  # iam_role_additional_policies = {
  #   s3_bucket_nodes = module.s3.s3_bucket_policy
  # }
}

# resource "aws_iam_role_policy_attachment" "ssm-policy" {
#   for_each = {
#     for index, group in module.k8s.eks_managed_node_groups :
#     index => group if var.enable_s3_buckets
#   }
#   role       = each.value.iam_role_name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }

##########################################
# ASG instances tags to be allocated
##########################################
resource "aws_autoscaling_group_tag" "asg-project" {
  for_each = {
    for index, group in module.k8s.eks_managed_node_groups :
    index => group
  }

  autoscaling_group_name = each.value.node_group_autoscaling_group_names[0]
  tag {
    key                 = "project"
    value               = "paas"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "eks-owner" {
  for_each = {
    for index, group in module.k8s.eks_managed_node_groups :
    index => group
  }
  autoscaling_group_name = each.value.node_group_autoscaling_group_names[0]
  tag {
    key                 = "owner"
    value               = "devops"
    propagate_at_launch = true
  }
}


resource "aws_autoscaling_group_tag" "asg-tenant" {
  for_each = {
    for index, group in module.k8s.eks_managed_node_groups :
    index => group
  }
  autoscaling_group_name = each.value.node_group_autoscaling_group_names[0]
  tag {
    key                 = "tenant"
    value               = var.name
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "asg-name" {
  for_each = {
    for index, group in module.k8s.eks_managed_node_groups :
    index => group
  }
  autoscaling_group_name = each.value.node_group_autoscaling_group_names[0]
  tag {
    key                 = "Name"
    value               = "${var.name}-${each.key}"
    propagate_at_launch = true
  }
}

#################################################
# EKS storage class to gp3 instead of gp2
#################################################
# Remove non encrypted default storage class
resource "kubernetes_annotations" "default-storageclass" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = "true"

  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
}

# Create the new wanted StorageClass and make it default
resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    "encrypted" = "true"
    "fsType"    = "ext4"
    "type"      = "gp3"
  }
}

##########################################
# EKS/K8S cluster data for communication
#########################################

data "aws_eks_cluster" "eks" {
  name = module.k8s.cluster_name
  lifecycle {
    precondition {
      condition     = module.k8s.cluster_name != null
      error_message = "Cluster still not created"
    }
  }
}

data "aws_eks_cluster_auth" "eks" {
  name = module.k8s.cluster_name
  lifecycle {
    precondition {
      condition     = module.k8s.cluster_name != null
      error_message = "Cluster still not created"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

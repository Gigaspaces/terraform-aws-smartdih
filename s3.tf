###########################################################
# Local veriables
###########################################################
locals {
  bucket_names = {
    data    = lower("gs-dih-${replace(local.name, "/\\W|_|\\s/", "-")}-data-${try(random_string.s3suffix[0].id, "")}")
    control = lower("gs-dih-${replace(local.name, "/\\W|_|\\s/", "-")}-control-${try(random_string.s3suffix[0].id, "")}")
  }

  s3_buckets_policy = "${replace(var.name, "/\\W|_|\\s/", "-")}-dih-s3-policy"
  s3_username       = "${replace(var.name, "/\\W|_|\\s/", "-")}-dih-s3-user"
}

# tflint-ignore: terraform_required_providers
resource "random_string" "s3suffix" {
  count   = var.enable_s3_buckets ? 1 : 0
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

###########################################################
# S3 buckets with policies
###########################################################
data "aws_iam_policy_document" "s3_data_bucket_policy" {
  count = var.enable_s3_buckets ? 1 : 0
  statement {
    principals {
      type = "AWS"
      identifiers = setunion([
        module.k8s.eks_managed_node_groups.worker.iam_role_arn,
        module.k8s.eks_managed_node_groups.generic.iam_role_arn,
        module.k8s.eks_managed_node_groups.ingress.iam_role_arn,
      ], var.enable_s3_data_user ? [module.s3-iam-user[0].iam_user_arn] : [])
    }

    sid = "FullBucketAccess"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      "arn:aws:s3:::${local.bucket_names.data}",
      "arn:aws:s3:::${local.bucket_names.data}/*",
    ]
  }
}

data "aws_iam_policy_document" "s3_control_bucket_policy" {
  count = var.enable_s3_buckets ? 1 : 0
  statement {
    principals {
      type = "AWS"
      identifiers = setunion([
        module.k8s.eks_managed_node_groups.worker.iam_role_arn,
        module.k8s.eks_managed_node_groups.generic.iam_role_arn,
        module.k8s.eks_managed_node_groups.ingress.iam_role_arn,
      ], var.enable_s3_data_user ? [module.s3-iam-user[0].iam_user_arn] : [])
    }

    sid = "FullBucketAccess"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      "arn:aws:s3:::${local.bucket_names.control}",
      "arn:aws:s3:::${local.bucket_names.control}/*",
    ]
  }
}


module "s3_data" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.14.0"
  count   = var.enable_s3_buckets ? 1 : 0

  bucket        = local.bucket_names.data
  acl           = "private"
  force_destroy = true
  tags          = local.tags

  attach_policy            = true
  policy                   = data.aws_iam_policy_document.s3_data_bucket_policy[0].json
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  cors_rule = var.s3_data_cors_rule
}

module "s3_control" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.14.0"
  count   = var.enable_s3_buckets ? 1 : 0

  bucket        = local.bucket_names.control
  acl           = "private"
  force_destroy = true
  tags          = local.tags

  attach_policy            = true
  policy                   = data.aws_iam_policy_document.s3_control_bucket_policy[0].json
  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"
}

###########################################################
# S3 buckets policy to be attached to nodes or IAM user
###########################################################
module "s3-bucket-policy" {
  count   = var.enable_s3_buckets ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.24.0"

  name = local.s3_buckets_policy
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "ListBucket"
        Effect : "Allow",
        Action : [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        Resource : [
          "arn:aws:s3:::${local.bucket_names["data"]}",
          "arn:aws:s3:::${local.bucket_names["control"]}",
        ]
      },
      {
        Sid = "FullBucketAccess"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ],
        Effect : "Allow",
        Resource = [
          "arn:aws:s3:::${local.bucket_names["data"]}/*",
          "arn:aws:s3:::${local.bucket_names["control"]}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks-node-s3-role-attachment" {
  for_each = {
    for index, group in module.k8s.eks_managed_node_groups :
    index => group if var.enable_s3_buckets
  }
  policy_arn = module.s3-bucket-policy[0].arn
  role       = each.value.iam_role_name
}

################################################################
# IAM user in case we want to use user and not via node role
################################################################
module "s3-iam-user" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "5.24.0"
  count   = var.enable_s3_buckets && var.enable_s3_data_user ? 1 : 0

  name                  = local.s3_username
  create_iam_access_key = true
  force_destroy         = true

  create_iam_user_login_profile = false

  depends_on = [kubernetes_namespace.dih]
}

resource "kubernetes_secret" "s3-user" {
  count = var.enable_s3_buckets && var.enable_s3_data_user ? 1 : 0
  metadata {
    name      = var.s3_username
    namespace = var.namespace
  }

  data = {
    ACCESS_KEY = module.s3-iam-user[0].iam_access_key_id
    SECRET_KEY = module.s3-iam-user[0].iam_access_key_secret
  }
}

resource "aws_iam_user_policy_attachment" "s3-user-attach" {
  count      = var.enable_s3_buckets && var.enable_s3_data_user ? 1 : 0
  user       = module.s3-iam-user[0].iam_user_name
  policy_arn = module.s3-bucket-policy[0].arn
}

##################################################
# Prepare sample data for demo space/pipeline
# ##################################################

resource "null_resource" "s3_objects" {
  count = var.enable_s3_buckets && var.enable_dih_default_space && var.copy_sample_data ? 1 : 0
  provisioner "local-exec" {
    command = "aws s3 cp s3://${var.sample_data_s3_bucket} s3://${local.bucket_names["data"]} --recursive"
  }

  depends_on = [module.s3_data]
}

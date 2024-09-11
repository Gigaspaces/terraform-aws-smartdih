###########################################################
# Local veriables
###########################################################
locals {
  spacedeck_s3_bucket_policy = "${replace(var.name, "/\\W|_|\\s/", "-")}-spacedeck-dih-s3-policy"
  dih_spacedeck_role         = "${replace(var.name, "/\\W|_|\\s/", "-")}-gs-dih-dih-spacedeck-role"
}

####################################################
# SpaceDeck Pod policy
####################################################
module "spacedeck-s3-bucket-policy" {
  count   = var.enable_spacedeck_iam_role && var.enable_s3_buckets ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.24.0"

  name = local.spacedeck_s3_bucket_policy
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
        Resource : "arn:aws:s3:::${local.bucket_names["data"]}"
      },
      {
        Sid = "WriteAccess"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ],
        Effect : "Allow",
        Resource = "arn:aws:s3:::${local.bucket_names["data"]}/*"
      }
    ]
  })
}

resource "aws_iam_role" "dih-spacedeck-role" {
  count = var.enable_spacedeck_iam_role ? 1 : 0
  name  = local.dih_spacedeck_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # {
      #   Effect    = "Allow"
      #   Sid       = "AssumeRole"
      #   Principal = {
      #     AWS = format("arn:aws:iam::%s:role/%s", local.account_id, local.dih_spacedeck_role)
      #   }
      #   Action: [
      #     "sts:AssumeRole",
      #     "sts:TagSession"
      #   ]
      # },

      {
        Effect = "Allow"
        Sid    = "AssumeRoleWeb"
        Principal = {
          Federated = module.k8s.oidc_provider_arn
        }
        Condition : {
          StringLike : {
            "${module.k8s.oidc_provider}:sub" : "system:serviceaccount:${var.namespace}:*spacedeck*"
          }
        }
        # Action: "sts:AssumeRoleWithWebIdentity"
        Action : [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "spacedeck-s3" {
  count      = var.enable_spacedeck_iam_role && var.enable_s3_buckets ? 1 : 0
  policy_arn = try(module.spacedeck-s3-bucket-policy[0].arn, null)
  role       = try(aws_iam_role.dih-spacedeck-role[0].name, null)
}

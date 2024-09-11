data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_policy" "clusternode" {
  name        = "${var.name}-cluster-node-policy"
  description = "Needed by EC2 worker instances to create EBS volumes used by GS DIH"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "PVolumeCreate"
        Action = [
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*",
        ]
      },
      {
        Sid = "Autoscaler"
        Action = [
          "cloudwatch:GetMetricData",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:BatchPutScheduledUpdateGroupAction",
          "autoscaling:BatchDeleteScheduledAction",
          "autoscaling:PutScalingPolicy",
          "autoscaling:DeletePolicy",
          "eks:DescribeNodegroup",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:autoscaling:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/*",

          "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:nodegroup/${local.cluster_name}/*",
        ]
      },
      {
        Sid      = "AutoscalerDescribe"
        Action   = ["autoscaling:Describe*"]
        Effect   = "Allow"
        Resource = ["*"]
      }
    ]
  })
}

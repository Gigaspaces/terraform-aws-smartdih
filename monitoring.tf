# Based on https://docs.fluentbit.io/manual/pipeline/outputs/opensearch
# data "aws_partition" "current" {}
locals {
  collection_name   = "${var.name}-collection"
  opensearch_policy = "${replace(var.name, "/\\W|_|\\s/", "-")}-dih-aoss-policy"
  extra_iam_roles = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Administrator-Role",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.noc_role_name}"
  ]
  fluentbit_helm_sets = {
    "config.outputs" = <<EOF
[OUTPUT]
    Name  opensearch
    Match *
    Host  ${try(split("https://", try(aws_opensearchserverless_collection.collection[0].collection_endpoint, ""))[1], "")}
    Port  443
    Index ${var.logging_index_name}
    Suppress_Type_Name On
    AWS_Auth On
    AWS_Region ${data.aws_region.current.name}
    AWS_Service_Name aoss
    tls     On
    Trace_Error On
EOF

    "config.filters" = <<EOF
[FILTER]
    Name kubernetes
    Match kube.*
    Merge_Log On
    Keep_Log Off
    K8S-Logging.Parser On
    K8S-Logging.Exclude On

[FILTER]
    Name modify
    Match *
    Add tenant ${var.name}
EOF
  }
}

#####################################
# Metrics server
#####################################
resource "helm_release" "metrics-server" {
  count            = var.enable_metrics_server ? 1 : 0
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.10.0"
  namespace        = var.addon_namespaces["metrics-server"]
  create_namespace = true

  values = [file("${path.module}/helm_values/metrics.yaml")]
}

#####################################
# Prometheus stack
#####################################
resource "random_password" "grafana_admin" {
  count   = var.grafana_admin_password == null ? 1 : 0
  length  = 16
  special = false
}

resource "helm_release" "prometheus" {
  count            = var.enable_prometheus ? 1 : 0
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_helm_version
  namespace        = var.addon_namespaces["prometheus"]
  create_namespace = true

  values = [file("${path.module}/helm_values/prometheus.yaml")]

  dynamic "set" {
    for_each = {
      "grafana.enabled" : true
      "grafana.adminUser" : var.grafana_admin
      "grafana.adminPassword" : local.grafana_password
      "grafana.ingress.enabled" : true
      "grafana.ingress.annotations.kubernetes\\.io\\/ingress\\.class" : coalesce(local.ingress_class, var.default_ingress_class)
      "grafana.ingress.hosts[0]" : local.grafana_ingress_host
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}

#############################################
# IAM policy to be added to EKS nodes
# Based on https://docs.aws.amazon.com/opensearch-service/latest/developerguide/security-iam-serverless.html#security_iam_id-based-policy-examples-data-plane.html
#############################################
module "opensearch-logging-policy" {
  count   = var.enable_logging ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "5.24.0"

  name = local.opensearch_policy
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "SendingLogsIndex"
        Effect : "Allow",
        Action : ["aoss:*"],
        Resource : "arn:aws:aoss:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:collection/${aws_opensearchserverless_collection.collection[0].id}"
      },
      {
        Sid : "AOSSDashboards",
        Effect : "Allow",
        Action : "aoss:DashboardsAccessAll",
        Resource : "arn:aws:aoss:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dashboards/default"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks-node-opensearch-role-attachment" {
  for_each = {
    for index, group in module.k8s.eks_managed_node_groups :
    index => group if var.enable_logging
  }
  policy_arn = module.opensearch-logging-policy[0].arn
  role       = each.value.iam_role_name
}

#############################################################################
# Deploy of Fluent-bit which has direct output plugin toward AWS OpenSearch
#############################################################################
resource "helm_release" "fluentbit" {
  count            = var.enable_logging ? 1 : 0
  name             = "fluent-bit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  version          = "0.36.0"
  namespace        = var.addon_namespaces["fluent-bit"]
  create_namespace = true
  wait_for_jobs    = true

  dynamic "set" {
    for_each = merge(var.default_fluentbit_helm_sets, local.fluentbit_helm_sets)
    content {
      name  = set.key
      value = set.value
    }
  }

  timeout    = 1200
  depends_on = [aws_iam_role_policy_attachment.eks-node-opensearch-role-attachment]
}

##################################################
# OpenSearch serverless collection
##################################################
resource "aws_opensearchserverless_security_policy" "encryption" {
  count = var.enable_logging ? 1 : 0
  name  = "${var.name}-encryption-policy"
  type  = "encryption"
  policy = jsonencode({
    Rules = [
      {
        Resource     = ["collection/${local.collection_name}"],
        ResourceType = "collection"
      }
    ],
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_access_policy" "access" {
  count = var.enable_logging ? 1 : 0
  name  = "${var.name}-data-access-policy"
  type  = "data"

  policy = jsonencode([
    {
      "Rules" : [
        {
          "ResourceType" : "collection",
          "Resource" : [
            "collection/${local.collection_name}"
          ],
          "Permission" : [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          "ResourceType" : "index",
          "Resource" : [
            "index/${local.collection_name}/*"
          ],
          "Permission" : [
            "aoss:CreateIndex",
            "aoss:DescribeIndex",
            "aoss:UpdateIndex",
            "aoss:DeleteIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        }
      ],
      "Principal" : concat(
        var.default_roles,
        local.extra_iam_roles,
      values({ for index, group in module.k8s.eks_managed_node_groups : index => group.iam_role_arn }))
    }
  ])
}

resource "aws_opensearchserverless_security_policy" "network" {
  count       = var.enable_logging ? 1 : 0
  name        = "${var.name}-network-policy"
  type        = "network"
  description = "Public access"
  policy = jsonencode([
    {
      Description = "Public access to DIH log collection",
      Rules = [
        {
          ResourceType = "collection",
          Resource     = ["collection/${local.collection_name}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/${local.collection_name}"]
        }
      ],
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_collection" "collection" {
  count = var.enable_logging ? 1 : 0
  name  = local.collection_name
  type  = "SEARCH" # TIMESERIES
  tags  = var.tags

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_access_policy.access,
    aws_opensearchserverless_security_policy.network
  ]
}

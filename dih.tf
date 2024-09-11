locals {
  ingress_host         = lower("${local.name}.${trim(data.aws_route53_zone.paas.name, ".")}")
  grafana_ingress_name = lower("${local.name}-grafana")
  grafana_ingress_host = lower("${local.name}-grafana.${trim(data.aws_route53_zone.paas.name, ".")}")

  dih_grafana_enabled = var.enable_prometheus ? false : true
  grafana_service_url = var.enable_prometheus ? "http://prometheus-grafana.${var.addon_namespaces["prometheus"]}.svc.cluster.local" : "http://grafana.${var.namespace}.svc.cluster.local"
  grafana_password    = coalesce(resource.random_password.grafana_admin[0].result, var.grafana_admin_password)

  dih_helm_value_files = length(var.dih_helm_value_files) > 0 ? var.dih_helm_value_files : concat(var.dih_sku_production ? ["dih-prod-values.yaml"] : ["dih-dev-values.yaml"], ["dih-node-selectors.yaml"])

}

#####################################
# DIH Helm
#####################################
resource "kubernetes_namespace" "dih" {
  count = var.enable_dih ? 1 : 0
  metadata {
    annotations = {
      name = var.namespace
    }
    name = var.namespace
  }

  depends_on = [module.k8s]
}

resource "kubernetes_secret" "dockerhub" {
  count = var.enable_dih ? 1 : 0
  metadata {
    name      = "myregistrysecret"
    namespace = var.namespace
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          username = var.dockerhub_user,
          password = var.dockerhub_pass,
          email    = var.dockerhub_email,
          auth     = base64encode("${var.dockerhub_user}:${var.dockerhub_pass}")
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"

  depends_on = [kubernetes_namespace.dih]
}


resource "random_password" "admin_password" {
  count   = var.dih_admin_password == null ? 1 : 0
  length  = 16
  special = false
}

resource "helm_release" "dih" {
  count            = var.enable_dih ? 1 : 0
  name             = "all-dih"
  repository       = var.dih_helm_repo
  chart            = "dih"
  version          = var.dih_helm_version
  namespace        = var.namespace
  create_namespace = false
  wait_for_jobs    = true
  force_update     = var.dih_force_update

  values = length(var.dih_helm_value_files) > 0 ? [for value in local.dih_helm_value_files : file("${path.module}/helm_values/${value}")] : []

  # "https://s3.amazonaws.com/resources.gigaspaces.com/helm-values/dih-prod-values.yaml"

  dynamic "set" {
    for_each = merge(var.dih_helm_default_sets, var.dih_helm_sets, {
      "manager.license" : var.dih_license
      "operator.license" : var.dih_license

      "tags.iidr" : var.dih_enable_iidr
      "tags.dgw" : var.dih_enable_datagw

      "global.ingressHost" : local.ingress_host
      "global.security.enabled" : var.dih_security_enabled
      "global.affinity.enabled" : var.azs_count == 3 ? true : false

      "manager.securityService.secretKeyRef.user" : base64encode(try(var.dih_admin_username, "admin"))
      "manager.securityService.secretKeyRef.password" : base64encode(try(random_password.admin_password[0].result, var.dih_admin_password))

      "ha" : var.enable_dih_ha
      "manager.ha" : var.enable_dih_ha
      "manager.metrics.influxdb.host" : "influxdb.${var.namespace}.svc.cluster.local"
      "manager.metrics.grafana.url" : local.grafana_service_url
      "manager.metrics.grafana.user" : var.grafana_admin
      "manager.metrics.grafana.password" : local.grafana_password

      "global.s3.enabled" : var.enable_s3_buckets
      "global.defaultBucket.bucket" : try(module.s3_data[0].s3_bucket_id, "")
      "global.defaultBucket.sorName" : var.s3_default_sor_name
      # "global.s3.defaultS3Bucket.bucket" : try(module.s3_data[0].s3_bucket_id, "")
      # "global.s3.defaultS3Bucket.sorName" : var.s3_default_sor_name
      "global.flink.highAvailability.bucket" : try(module.s3_control[0].s3_bucket_id, "")

      "spacedeck.ingress.class" : coalesce(local.ingress_class, var.default_ingress_class)

      "service-creator.ingress.class" : coalesce(local.ingress_class, var.default_ingress_class)

      "manager.securityService.ingress.class" : coalesce(local.ingress_class, var.default_ingress_class)

      "grafana.ingress.enabled" : local.dih_grafana_enabled
      "grafana.ingress.hosts[0]" : local.grafana_ingress_host
      "grafana.ingress.ingressClassName" : coalesce(local.ingress_class, var.default_ingress_class)

      "grafana.enabled" : local.dih_grafana_enabled
      "grafana.adminUser" : var.grafana_admin
      "grafana.adminPassword" : local.grafana_password

      "kafka.controller.persistence.size" : coalesce(var.dih_kafka_pvc_size, "50Gi")
      "zookeeper.persistence.size" : coalesce(var.dih_zookeeper_pvc_size, "10Gi")
    })
    content {
      name  = set.key
      value = set.value
    }
  }

  timeout = 1200
  depends_on = [
    module.vpc,
    module.k8s,
    kubernetes_secret.dockerhub,
    helm_release.ingress_external,
    helm_release.ingress_internal,
    helm_release.prometheus,
  ]
}

#####################################
# DIH Default XAP spaces
#####################################
resource "helm_release" "dih-default-space" {
  count            = var.enable_dih_default_space ? 1 : 0
  name             = var.dih_default_space_name
  repository       = var.dih_helm_repo
  chart            = "xap-pu"
  version          = var.dih_helm_version
  namespace        = var.namespace
  create_namespace = false
  wait_for_jobs    = true

  dynamic "set" {
    for_each = merge(var.dih_default_space_helm_sets, {
      "license" : var.dih_license
      "properties[0].name" : "dataGridName"
      "properties[0].value" : var.dih_default_space_name
      "properties[1].name" : "secured"
      "properties[1].value" : "\"${var.dih_security_enabled}\""
    })
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [helm_release.dih]
}

#####################################
# DIH Oracle IIDR for data injection
#####################################
resource "kubernetes_secret" "datastore" {
  count = var.enable_dih && var.enable_dih_oracle && var.dih_enable_iidr ? 1 : 0
  metadata {
    name      = "datastore-credentials"
    namespace = var.namespace
  }

  data = var.dih_oracle_datastore_secret

  depends_on = [helm_release.dih]
}

resource "helm_release" "dih-oracle" {
  count            = var.enable_dih_oracle && var.dih_enable_iidr ? 1 : 0
  name             = "oracledb"
  repository       = var.dih_helm_repo
  chart            = "di-oracle"
  version          = "2.0.2"
  namespace        = var.namespace
  create_namespace = false
  wait_for_jobs    = true

  dynamic "set" {
    for_each = var.dih_oracle_helm_sets
    content {
      name  = set.key
      value = set.value
    }
  }

  timeout    = 1200
  depends_on = [kubernetes_secret.datastore]
}

#####################################
# DIH Postgresql as DGW replacement
#####################################
resource "helm_release" "postgresql" {
  count            = var.enable_dih_postgresql ? 1 : 0
  name             = "psql"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "postgresql"
  version          = "12.6.6"
  namespace        = var.namespace
  create_namespace = false
  wait_for_jobs    = true

  dynamic "set" {
    for_each = merge(var.dih_default_postgresql_helm_sets, var.dih_postgresql_helm_sets)
    content {
      name  = set.key
      value = set.value
    }
  }

  timeout    = 1200
  depends_on = [kubernetes_secret.datastore]
}

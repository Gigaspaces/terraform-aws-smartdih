locals {
  ingress_class = var.enable_public_ingress && !var.enable_internal_ingress ? "nginx" : (!var.enable_public_ingress && var.enable_internal_ingress ? "nginx" : null)

  ingress_tcp_rules = merge(var.ingress_tcp_rules,
    var.dih_enable_datagw ? { 5432 = "${var.namespace}/xap-dgw-service:5432" } : {},
    var.dih_enable_iidr ? { 11701 = "${var.namespace}/iidr-kafka:11701" } : {}
  )
}

#####################################
# NGINX Ingress
#####################################
resource "helm_release" "ingress_internal" {
  count            = var.enable_internal_ingress ? 1 : 0
  name             = "ingress-internal"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_ingress_helm_version
  namespace        = var.addon_namespaces["ingress-internal"]
  create_namespace = true

  values = [templatefile("${path.module}/helm_values/private_nginx_ingress.yaml", {
    ingress_class = coalesce(local.ingress_class, "nginx-internal")
    default       = !var.enable_public_ingress && var.enable_internal_ingress
    node_selector = "gs-nodegroup: ingress"

    load_balancer_subnets = join(",", coalesce(var.private_subnet_ids, try(module.vpc[0].private_subnets, null)))
    nodegroup_labels      = "gs-nodegroup=ingress"
    lb_tags               = "Name=paas-${var.name}-internal,${join(",", [for key, value in var.tags : "${key}=${value}"])}",
    ingress_cert          = var.dih_ingress_cert
    allowed_cidr_blocks   = join(",", setunion(var.whitelist_cidrs, [var.cidr_block]))
  })]


  dynamic "set" {
    for_each = local.ingress_tcp_rules
    content {
      name  = "tcp.${set.key}"
      value = set.value
    }
  }
}

resource "helm_release" "ingress_external" {
  count            = var.enable_public_ingress ? 1 : 0
  name             = "ingress-external"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_ingress_helm_version
  namespace        = var.addon_namespaces["ingress-external"]
  create_namespace = true

  values = [templatefile("${path.module}/helm_values/public_nginx_ingress.yaml", {
    ingress_class = coalesce(local.ingress_class, "nginx-external")
    default       = !var.enable_public_ingress && var.enable_internal_ingress
    node_selector = "gs-nodegroup: ingress"

    load_balancer_subnets = join(",", coalesce(var.public_subnet_ids, try(module.vpc[0].public_subnets, null)))
    nodegroup_labels      = "gs-nodegroup=ingress"
    lb_tags               = "Name=paas-${var.name}-public,${join(",", [for key, value in var.tags : "${key}=${value}"])}",
    ingress_cert          = var.dih_ingress_cert
    allowed_cidr_blocks   = join(",", setunion(var.whitelist_cidrs, [var.cidr_block]))
  })]


  dynamic "set" {
    for_each = local.ingress_tcp_rules
    content {
      name  = "tcp.${set.key}"
      value = set.value
    }
  }
}

######################################################
# Route53 record pointing to DIH spacedeck
######################################################
data "aws_route53_zone" "paas" {
  name         = var.dih_dns_zone
  private_zone = false
}

data "kubernetes_service" "public_ingress_nginx" {
  count = var.enable_public_ingress ? 1 : 0
  metadata {
    name      = coalesce("${helm_release.ingress_external[0].name}-ingress-nginx-controller", "ingress-nginx-controller")
    namespace = var.addon_namespaces["ingress-external"]
  }
}

data "kubernetes_service" "internal_ingress_nginx" {
  count = var.enable_internal_ingress ? 1 : 0
  metadata {
    name      = coalesce("${helm_release.ingress_internal[0].name}-ingress-nginx-controller", "ingress-nginx-controller")
    namespace = var.addon_namespaces["ingress-internal"]
  }
}

resource "aws_route53_record" "spacedeck" {
  count   = var.enable_public_ingress || var.enable_internal_ingress ? 1 : 0
  zone_id = data.aws_route53_zone.paas.zone_id
  name    = local.name
  type    = "CNAME"
  ttl     = "3600"
  records = [coalesce(try(data.kubernetes_service.public_ingress_nginx[0].status[0].load_balancer[0].ingress[0].hostname, null), try(data.kubernetes_service.internal_ingress_nginx[0].status[0].load_balancer[0].ingress[0].hostname, null), null)]
}

resource "aws_route53_record" "grafana" {
  count   = var.enable_public_ingress || var.enable_internal_ingress ? 1 : 0
  zone_id = data.aws_route53_zone.paas.zone_id
  name    = local.grafana_ingress_name
  type    = "CNAME"
  ttl     = "3600"
  records = [coalesce(try(data.kubernetes_service.public_ingress_nginx[0].status[0].load_balancer[0].ingress[0].hostname, null), try(data.kubernetes_service.internal_ingress_nginx[0].status[0].load_balancer[0].ingress[0].hostname, null), null)]
}

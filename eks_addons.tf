#####################################
# Certificate manager
#####################################
resource "helm_release" "cert-manager" {
  count            = var.enable_cert_manager ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cm_helm_version
  namespace        = var.addon_namespaces["cert-manager"]
  create_namespace = true

  values = [file("${path.module}/helm_values/cert_manager.yaml")]
}


#####################################
# AWS cluster autoscaller
#####################################
resource "helm_release" "cluster-autoscaler" {
  count            = var.enable_cluster_autoscaler ? 1 : 0
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = var.autoscaler_helm_version
  namespace        = var.addon_namespaces["cluster-autoscaler"]
  create_namespace = false

  values = [file("${path.module}/helm_values/autoscaler.yaml")]


  set {
    name  = "autoDiscovery.clusterName"
    value = local.cluster_name
  }
  set {
    name  = "awsRegion"
    value = data.aws_region.current.name
  }
}

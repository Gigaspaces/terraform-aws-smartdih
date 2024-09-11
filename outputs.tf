output "vpc" {
  value = merge(
    length(module.vpc) > 0 ? module.vpc[0] : null,
    length(data.aws_vpc.this) > 0 ? data.aws_vpc.this[0] : null
  )
}

output "s3_buckets" {
  value = var.enable_s3_buckets ? {
    control = module.s3_control[0].s3_bucket_id
    data    = module.s3_data[0].s3_bucket_id
  } : null
}

output "vpn_endpoint" {
  value = try(format("https://%s", aws_eip.public[0].public_ip), null)
}

output "opensearch_dashboard_endpont" {
  value = try(aws_opensearchserverless_collection.collection[0].dashboard_endpoint, null)
}

output "spacedeck" {
  value = {
    url      = "https://${local.ingress_host}"
    username = var.dih_admin_username
    password = coalesce(random_password.admin_password[0].result, var.dih_admin_password)
  }
  sensitive = true
}

output "grafana" {
  value = {
    url      = "https://${local.grafana_ingress_host}"
    user     = var.grafana_admin
    password = local.grafana_password
  }

  sensitive = true
}

output "s3_iam_credentials" {
  value = try({
    AWS_ACCESS_KEY_ID     = base64encode(module.s3-iam-user[0].iam_access_key_id)
    AWS_SECRET_ACCESS_KEY = base64encode(module.s3-iam-user[0].iam_access_key_secret)
    AWS_REGION            = data.aws_region.current.name
  }, null)
  sensitive = true
}

output "bastion_ip_address" {
  value = length(module.bastion) > 0 ? try({
    public_ip  = module.bastion[0].public_ip,
    private_ip = module.bastion[0].private_ip
  }) : null
}

output "bastion_public_key_pem" {
  value     = try(module.key_pair[0].public_key_pem, null)
  sensitive = true
}

output "bastion_private_key_pem" {
  value     = try(module.key_pair[0].private_key_pem, null)
  sensitive = true
}

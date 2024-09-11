data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = replace(var.name, "/\\W|_|\\s/", "-")
  azs  = slice(data.aws_availability_zones.available.names, 0, length(data.aws_availability_zones.available.names) >= var.azs_count ? var.azs_count : 2)

  tags = merge(var.tags, {
    terraform = true
  })

  private_inbound_acl_rules = concat(
    [{
      cidr_block : var.cidr_block,
      from_port : 0,
      protocol : -1,
      rule_action : "allow",
      rule_number : 100,
      to_port : 0
    }],
    [for index, block in var.whitelist_cidrs : {
      cidr_block  = block,
      from_port   = 0,
      protocol    = -1,
      rule_action = "allow",
      rule_number = 101 + index,
      to_port     = 0
      }
  ])
}

#####################################
# VPC Module
#####################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"
  count   = var.vpc_id == null ? 1 : 0

  name = var.name
  cidr = var.cidr_block
  azs  = local.azs

  private_subnets = length(var.private_subnets) != 0 ? var.private_subnets : [for k, v in local.azs : cidrsubnet(var.cidr_block, 4, k)]
  public_subnets  = length(var.public_subnets) != 0 ? var.public_subnets : [for k, v in local.azs : cidrsubnet(var.cidr_block, 4, k + 4)]

  manage_default_network_acl    = var.manage_defaults
  manage_default_route_table    = var.manage_defaults
  manage_default_security_group = var.manage_defaults

  private_dedicated_network_acl = var.private_dedicated_network_acl
  private_inbound_acl_rules     = local.private_inbound_acl_rules

  enable_dns_hostnames = var.dns_support
  enable_dns_support   = var.dns_support

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway
  nat_gateway_tags   = { Name = "${var.name}-dih-nat" }

  create_igw = var.create_igw
  igw_tags   = { Name = "${var.name}-dih-igw" }

  customer_gateways  = var.customer_gateways
  enable_vpn_gateway = var.enable_vpn_gateway
  vpn_gateway_tags   = { Name = "${var.name}-dih-vpn-gw" }

  tags = local.tags
}

data "aws_vpc" "this" {
  count = var.vpc_id == null ? 1 : 0
  id    = coalesce(var.vpc_id, length(module.vpc) > 0 ? module.vpc[0].vpc_id : null)
}

module "vpn_gw" {
  count   = var.enable_vpn_gateway ? 1 : 0
  source  = "terraform-aws-modules/vpn-gateway/aws"
  version = "3.5.0"

  vpc_id              = coalesce(var.vpc_id, try(module.vpc.vpc_id, null))
  vpn_gateway_id      = coalesce(var.vpn_gateway_id, try(module.vpc.vgw_id, null))
  customer_gateway_id = coalesce(var.customer_gateway_id, try(module.vpc.cgw_ids[0], null))

  vpc_subnet_route_table_count = length(concat(
    coalesce(var.private_route_table_ids, try(module.vpc.private_route_table_ids, null)),
    coalesce(var.public_route_table_ids, try(module.vpc.public_route_table_ids, null))
  ))

  vpc_subnet_route_table_ids = concat(
    coalesce(var.private_route_table_ids, try(module.vpc.private_route_table_ids, null)),
    coalesce(var.public_route_table_ids, try(module.vpc.public_route_table_ids, null))
  )

  vpn_connection_static_routes_only         = true
  vpn_connection_static_routes_destinations = var.whitelist_cidrs

  tags = merge(local.tags, { Name = "${var.name}-dih-vpn-gw" })
}

module "vpc_peering" {
  count   = var.enable_vpn_gateway ? length(keys(var.vpc_peerings)) : 0
  source  = "cloudposse/vpc-peering/aws"
  version = "0.11.0"

  name      = keys(var.vpc_peerings)[count.index]
  stage     = "${var.name}-${keys(var.vpc_peerings)[count.index]}"
  namespace = "${var.name}-${keys(var.vpc_peerings)[count.index]}"
  tags      = merge(local.tags, { Name : "${var.name}-${keys(var.vpc_peerings)[count.index]}" })

  requestor_vpc_id = coalesce(var.vpc_id, try(module.vpc.vpc_id, null))
  acceptor_vpc_id  = values(var.vpc_peerings)[count.index].acceptor_vpc_id

  acceptor_vpc_tags         = values(var.vpc_peerings)[count.index].acceptor_vpc_tags
  acceptor_ignore_cidrs     = values(var.vpc_peerings)[count.index].acceptor_ignore_cidrs
  acceptor_route_table_tags = values(var.vpc_peerings)[count.index].acceptor_route_table_tags
  auto_accept               = values(var.vpc_peerings)[count.index].auto_accept

  acceptor_allow_remote_vpc_dns_resolution = values(var.vpc_peerings)[count.index].acceptor_allow_remote_vpc_dns_resolution
}

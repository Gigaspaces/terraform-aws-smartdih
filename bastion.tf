###########################################
# Bastion EC2 instance for WireGuard VPN
###########################################

locals {
  ssh_key_name = coalesce(var.ssh_key_name, "${var.name}-bastion-key")
}
module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "~> 2.0"

  count              = var.enable_bastion && var.ssh_public_key == null ? 1 : 0
  key_name           = local.ssh_key_name
  public_key         = var.ssh_public_key
  create_private_key = var.ssh_public_key == null ? true : false
}



module "bastion-sg" {
  count   = var.enable_bastion ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.17"

  name   = "${var.name}-bastion-sg"
  vpc_id = coalesce(var.vpc_id, try(module.vpc.vpc_id, null))

  egress_rules        = ["all-all"]
  ingress_cidr_blocks = length(var.whitelist_cidrs) > 0 ? var.whitelist_cidrs : ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp"] #"ssh-tcp"

  ingress_with_cidr_blocks = [
    { description = "WireGuardUDP"
      from_port   = 51820
      to_port     = 51820
      protocol    = "udp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      description = "WireGuardTCP"
      from_port   = 51820
      to_port     = 51820
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    { description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = var.tags
}

resource "aws_eip" "public" {
  count    = var.enable_bastion ? 1 : 0
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.name}-bastion-public-ip" })
  instance = module.bastion[0].id
}

module "bastion" {
  count   = var.enable_bastion ? 1 : 0
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 4.3.1"

  create_iam_instance_profile = true

  name          = "${var.name}-bastion"
  iam_role_name = "${var.name}-bastion-iam-role"
  ami           = var.ami
  key_name      = local.ssh_key_name

  subnet_id              = coalesce(var.public_subnet_ids[0], try(module.vpc.public_subnets[0], null))
  vpc_security_group_ids = [module.bastion-sg[0].security_group_id]
  #   associate_public_ip_address = true
  volume_tags = var.tags
  tags        = var.tags
  user_data   = var.bastion_user_data

  root_block_device = [{
    volume_size = 30
    encrypted   = true
    volume_type = "gp3"
  }]
}

resource "aws_iam_role_policy_attachment" "ssm-policy" {
  count      = length(module.bastion) > 0 ? 1 : 0
  role       = lookup(module.bastion[0], "iam_role_name", null)
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

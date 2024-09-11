variable "name" {
  type        = string
  description = "Name of the DIH installation, usually same as customer name"
}

variable "cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC. Not used if 'vpc_id' is defined"
}

variable "private_subnets" {
  type        = list(string)
  default     = []
  description = "List of private subnet CIDR blocks"
}

variable "public_subnets" {
  type        = list(string)
  default     = []
  description = "List of public subnet CIDR blocks"
}

variable "dns_support" {
  type        = bool
  default     = true
  description = "Indicates whether DNS resolution is supported"
}

variable "manage_defaults" {
  type        = bool
  default     = false
  description = "Indicates whether to manage default settings"
}

variable "enable_nat_gateway" {
  type        = bool
  default     = true
  description = "Indicates whether to enable NAT gateways"
}

variable "single_nat_gateway" {
  type        = bool
  default     = true
  description = "Indicates whether to use a single NAT gateway"
}

variable "create_igw" {
  type        = bool
  default     = true
  description = "Indicates whether to create an Internet Gateway"
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
}

variable "azs_count" {
  type        = number
  default     = 3
  description = "The number of availability zones"
}


variable "vpc_id" {
  type        = string
  default     = null
  description = "VPC ID when using customer VPC"
}

variable "private_subnet_ids" {
  type    = list(string)
  default = null
}

variable "public_subnet_ids" {
  type    = list(string)
  default = null
}

variable "vpn_gateway_id" {
  type    = string
  default = null
}

variable "customer_gateway_id" {
  type    = string
  default = null
}

variable "private_route_table_ids" {
  type    = list(string)
  default = null
}

variable "public_route_table_ids" {
  type    = list(string)
  default = null
}

variable "cluster_name" {
  type        = string
  default     = null
  description = "EKS cluster name"
}

variable "eks_version" {
  type        = string
  default     = "1.29"
  description = "The version of Amazon EKS"
}

variable "cluster_endpoint_public_access" {
  type        = bool
  default     = false
  description = "Indicates whether the public endpoint is enabled for the Kubernetes API server"
}

variable "cluster_endpoint_private_access" {
  type        = bool
  default     = true
  description = "Indicates whether the private endpoint is enabled for the Kubernetes API server"
}

variable "manage_aws_auth_configmap" {
  type        = bool
  default     = true
  description = "Indicates whether to manage the AWS auth ConfigMap"
}

variable "create_aws_auth_configmap" {
  type        = bool
  default     = false
  description = "Indicates whether to create the AWS auth ConfigMap"
}

variable "aws_auth_roles" {
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  description = "List of AWS IAM roles to add to the Kubernetes config map"
  default     = null
}

variable "cluster_addons" {
  type        = map(any)
  description = "Map of EKS cluster addons settings"
  default = {
    coredns = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
  }
}

variable "managed_node_groups" {
  type        = any
  description = "Map of settings for managed node groups"
  default     = {}
}

variable "default_managed_node_groups" {
  description = "Default settings for EKS managed node groups"
  type = map(object({
    ami_type                     = optional(string, "AL2_x86_64")
    min_size                     = optional(number, 1)
    max_size                     = optional(number, 10)
    desired_size                 = optional(number, 1)
    instance_types               = optional(list(string), ["t3.small"])
    capacity_type                = optional(string, "ON_DEMAND")
    disk_size                    = optional(number, 20)
    labels                       = optional(map(string), {})
    tags                         = optional(map(string), {})
    use_custom_launch_template   = optional(bool, false)
    force_update_version         = optional(bool, true)
    iam_role_additional_policies = optional(map(string), {})
    taints                       = optional(list(map(string)), [])
    enable_bootstrap_user_data   = optional(bool, false)
    post_bootstrap_user_data     = optional(string, null)
  }))

  validation {
    condition = alltrue([for key, value in var.default_managed_node_groups :
    value.capacity_type == "ON_DEMAND" || value.capacity_type == "SPOT"])
    error_message = "Invalid capacity_type type, 'ON_DEMAND' or 'SPOT'"
  }

  default = {
    ingress = {
      min_size       = 2
      max_size       = 2
      desired_size   = 2
      instance_types = ["t3a.small"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 30
      labels         = { gs-nodegroup = "ingress" }
      taints = [
        {
          key    = "dedicated"
          value  = "ingress"
          effect = "NO_SCHEDULE"
        }
      ]
    }
    worker = {
      min_size       = 1
      max_size       = 10
      desired_size   = 3
      instance_types = ["m5a.xlarge"]
      # disk_size      = 50
      labels        = { gs-nodegroup = "worker" }
      capacity_type = "ON_DEMAND"
      update_config = {
        max_unavailable_percentage = 30
      }
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size : 100
            volume_type : "gp3"
            delete_on_termination : true
          }
        }
      }
    }
    generic = {
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      instance_types = ["m5a.large"]
      disk_size      = 30
      labels         = { gs-nodegroup = "generic" }
      capacity_type  = "ON_DEMAND"
    }
  }
}

variable "node_security_group_additional_rules" {
  description = "Map of additional security group rules for nodes"
  type        = map(any)
  default = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }
}

variable "whitelist_cidrs" {
  type        = list(string)
  description = "List of CIDRs to whitelist for incoming traffic"
  default     = ["0.0.0.0/0"]
}

variable "k8s_whitelist_cidrs" {
  type        = list(string)
  description = "List of CIDRs to whitelist for incoming traffic to the Kubernetes API server"
  default     = ["0.0.0.0/0"]
}

variable "noc_role_name" {
  type    = string
  default = "paas-noc-admin-role"
}

variable "eks_managed_node_group_defaults" {
  type        = any
  description = "Default settings for all EKS managed node groups"
  default = {
    ami_type                   = "AL2_x86_64"
    instance_types             = ["m6i.large", "m5.large", "m5n.large", "m5zn.large"]
    use_custom_launch_template = true
    iam_role_additional_policies = {
      ssm-policy = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    enable_bootstrap_user_data = true
    post_bootstrap_user_data   = <<-EOT
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="==BOUNDARY=="

      --==BOUNDARY==
      Content-Type: text/cloud-boothook; charset="us-ascii"

      sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
      sudo systemctl enable amazon-ssm-agent
      sudo systemctl start amazon-ssm-agent

      --==BOUNDARY==--
    metadata_options:
      http_endpoint: enabled
      http_put_response_hop_limit: 2
      http_tokens: optional
    EOT
  }
}

variable "kms_enable" {
  type        = bool
  description = "Indicates whether to enable AWS Key Management Service (KMS)"
  default     = false
}

variable "enable_metrics_server" {
  type        = bool
  default     = true
  description = "Indicates whether to enable the Metrics Server for Kubernetes"
}

variable "enable_prometheus" {
  type        = bool
  default     = true
  description = "Indicates whether to enable Prometheus for monitoring"
}

variable "enable_internal_ingress" {
  type        = bool
  default     = false
  description = "Indicates whether to enable internal ingress with balancer"
}

variable "enable_public_ingress" {
  type        = bool
  default     = true
  description = "Indicates whether to enable public ingress with balancer"
}

variable "enable_cert_manager" {
  type        = bool
  default     = true
  description = "Indicates whether to enable Cert Manager for handling TLS certificates"
}

variable "private_dedicated_network_acl" {
  type        = bool
  default     = false
  description = "Indicates whether to use a private dedicated network ACL"
}

variable "enable_vpn_gateway" {
  type        = bool
  default     = false
  description = "Indicates whether to enable a VPN gateway"
}

variable "customer_gateways" {
  type = map(object({
    bgp_asn     = optional(number, 65112)
    ip_address  = optional(string, "1.2.3.4")
    device_name = optional(string, "VPN")
    type        = optional(string, "ipsec.1")
  }))
  description = "Map of customer gateways for VPN connections"
  default     = {}
}

variable "vpc_peerings" {
  type = map(object({
    acceptor_vpc_id           = string
    acceptor_vpc_tags         = optional(map(string), {})
    acceptor_ignore_cidrs     = optional(list(string), [])
    acceptor_route_table_tags = optional(map(any), {})
    auto_accept               = optional(bool, true)

    acceptor_allow_remote_vpc_dns_resolution = optional(bool, true)
  }))
  description = "Map of VPC peerings settings"
  default     = {}
}

variable "dih_helm_default_sets" {
  type        = map(string)
  description = "Map of default settings for the Data Integration Hub Helm chart"
  default = {
    "global.security.enabled" : true
    "global.s3.enabled" : false
    "manager.service.lrmi.enabled" : false
    "manager.metrics.enabled" : true
  }
}

variable "dih_helm_sets" {
  type        = map(string)
  description = "Map of custom settings for the Data Integration Hub Helm chart"
  default     = {}
}

variable "enable_dih" {
  type        = bool
  description = "Indicates whether to install DIH helm"
  default     = true
}

variable "enable_dih_ha" {
  type        = bool
  description = "Indicates whether to enable high availability for Data Integration Hub"
  default     = true
}

variable "dih_admin_username" {
  type        = string
  description = "Admin username for Data Integration Hub / Spacedeck"
  default     = "admin"
}

variable "dih_admin_password" {
  type        = string
  description = "Admin password for Data Integration Hub (generated if not set)"
  default     = null
}

variable "dih_enable_datagw" {
  type        = bool
  description = "Indicates whether to enable the Data Gateway for Data Integration Hub"
  default     = true
}

variable "dih_enable_iidr" {
  type        = bool
  description = "Indicates whether to enable IBM InfoSphere Data Replication (IIDR) for Data Integration Hub"
  default     = false
}

variable "dih_security_enabled" {
  type        = bool
  description = "Indicates whether to enable security features for Data Integration Hub"
  default     = true
}

variable "dih_license" {
  type        = string
  description = "Gigaspaces Smart DIH license key"
  default     = null
}

variable "dih_oracle_helm_sets" {
  type        = map(string)
  description = "Map of settings for Oracle Helm charts in Data Integration Hub"
  default = {
    "diOracleDB.volumes.oracledb.resources.requests.storage" : "20Gi"
  }
}

variable "dih_default_space_helm_sets" {
  type        = map(string)
  description = "Map of default space default settings in Data Integration Hub"
  default = {
    "ha" : true
    "java.options" : "-Dtimeout=60000"
    "nodeSelector.enabled" : true
    "nodeSelector.selector" : "gs-nodegroup:worker"
    "resources.limits.memory" : "1000Mi"
    "partitions" : 2
    "metrics.enabled" : true
  }
}

variable "dih_default_space_name" {
  type        = string
  description = "Default space name in Data Integration Hub"
  default     = "demo"
}


variable "dih_helm_version" {
  type        = string
  description = "Version of the Data Integration Hub Helm chart"
  default     = "16.5.0"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for Data Integration Hub"
  default     = "dih"
}

variable "dih_helm_repo" {
  type        = string
  description = "Helm chart repository for Data Integration Hub installation"
  default     = "https://s3.amazonaws.com/resources.gigaspaces.com/helm-charts-dih"
}

variable "dockerhub_user" {
  type        = string
  description = "DockerHub username for Data Integration Hub"
}

variable "dockerhub_pass" {
  type        = string
  description = "DockerHub password for Data Integration Hub"
}

variable "dockerhub_email" {
  type        = string
  description = "DockerHub email for Data Integration Hub"
  default     = "dih-customers@gigaspaces.com"
}

variable "dih_dns_zone" {
  type        = string
  description = "DNS zone for Data Integration Hub used by AWS Route53"
  default     = "paas.gigaspaces.net"
}

variable "dih_ingress_cert" {
  type        = string
  description = "AWS SSL certificate ARN for Data Integration Hub Ingress controller"
  default     = null
}

variable "addon_namespaces" {
  type        = map(string)
  description = "Map of namespace names for additional add-ons in Data Integration Hub"
  default = {
    prometheus : "monitoring"
    cert-manager : "cert-manager"
    metrics-server : "metrics-server"
    ingress-internal : "ingress-internal"
    ingress-external : "ingress-external"
    cluster-autoscaler : "kube-system"
    fluent-bit : "fluent-bit"
  }
}

variable "enable_dih_oracle" {
  type        = bool
  description = "Indicates whether to enable Oracle integration in Data Integration Hub"
  default     = false
}

variable "dih_oracle_datastore_secret" {
  type = object({
    username = string
    password = string
  })
  description = "Map of credentials for the Oracle Datastore in Data Integration Hub"
}

variable "enable_dih_default_space" {
  type        = bool
  description = "Indicates whether to enable the default space in Data Integration Hub"
  default     = true
}

variable "enable_s3_buckets" {
  type        = bool
  description = "Indicates whether to enable S3 buckets in Data Integration Hub"
  default     = true
}

variable "enable_s3_data_user" {
  type        = bool
  description = "Indicates whether to enable a separate S3 data user in DIH"
  default     = false
}

variable "s3_data_cors_rule" {
  type        = list(any)
  description = "List of CORS rules for the S3 bucket in Data Integration Hub"
  default = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "POST", "PUT", "DELETE", "HEAD"]
      allowed_origins = ["*"]

      expose_headers  = ["ETag", "x-amz-server-side-encryption", "x-amz-request-id", "x-amz-id-2"]
      max_age_seconds = 3000
    }
  ]
}

variable "s3_username" {
  type        = string
  description = "Username for the S3 data user in Data Integration Hub"
  default     = "s3-user"
}

variable "ingress_tcp_rules" {
  type        = map(string)
  description = "Map of TCP rules for ingress contoller"
  default     = {}
}

variable "grafana_admin" {
  type        = string
  description = "Grafana Admin username in Data Integration Hub"
  default     = "admin"
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana Admin password in Data Integration Hub(set to null for autogeneration)"
  default     = null
}


variable "enable_cluster_autoscaler" {
  type        = bool
  description = "Indicates whether to enable the Kubernetes Cluster Autoscaler"
  default     = false
}

variable "dih_helm_value_files" {
  type        = list(string)
  description = "List of additional Helm value files for Data Integration Hub"
  default     = []
}

variable "dih_force_update" {
  type        = bool
  description = "Indicates whether to force Helm updates"
  default     = false
}

variable "enable_dih_postgresql" {
  type        = bool
  description = "Indicates whether to enable PostgreSQL as replacer for DataGw"
  default     = false
}

variable "dih_postgresql_helm_sets" {
  type        = map(string)
  description = "Map of settings for PostgreSQL Helm charts in Data Integration Hub"
  default     = {}
}

variable "dih_default_postgresql_helm_sets" {
  type        = map(string)
  description = "Map of default settings for PostgreSQL Helm charts in Data Integration Hub"
  default = {
    "auth.enablePostgresUser" : true
    "primary.nodeSelector" : "gs-nodegroup: worker"
    "primary.resources.requests.memory" : "256Mi"
    "primary.resources.limits.memory" : "2000Mi"
    "primary.resources.requests.cpu" : "250m"
    "global.postgresql.auth.database" : "demo"
    "replication.numSynchronousReplicas" : 1
    "readReplicas.nodeSelector" : "gs-nodegroup: worker"
  }
}

variable "ssh_key_name" {
  type        = string
  default     = null
  description = "SSH key name"
}

variable "ssh_public_key" {
  type        = string
  default     = null
  description = "SSH public key"
}

variable "ami" {
  type        = string
  default     = null
  description = "Bastion AMI image"
}

variable "enable_bastion" {
  type        = bool
  description = "Created bastion VM with WireGuard VPN"
  default     = false
}

variable "bastion_user_data" {
  type        = string
  description = "Bastion installation script"
  default     = <<-EOT
    #!/bin/bash

    sudo amazon-linux-extras install -y kernel-5.10
    sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    sudo systemctl enable amazon-ssm-agent ; systemctl start amazon-ssm-agent

    # install basic packages
    sudo yum install -y vim docker yum-utils telnet kernel-headers-$(uname -r) kernel-devel-$(uname -r)
    sudo systemctl enable docker ; systemctl start docker

    touch /root/created
    yum update
    reboot
EOT
}

variable "enable_logging" {
  type        = bool
  description = "Indicates whether EKS pod logging is enabled"
  default     = false
}

variable "default_fluentbit_helm_sets" {
  type        = map(string)
  description = "Map of default settings for Fluent Bit Helm chart"
  default     = {}
}

variable "logging_index_name" {
  type        = string
  description = "AWS OpenSearch Index name for logging"
  default     = "dih-logs"
}

variable "default_roles" {
  type        = list(string)
  description = "List of default IAM roles added to EKS auth-conf configmap"
  default     = []
}

variable "enable_spacedeck_iam_role" {
  type        = bool
  description = "Indicates whether to enable the IAM role for SpaceDeck"
  default     = true
}

variable "sample_data_s3_bucket" {
  type        = string
  description = "S3 bucket for sample data for initial provisining"
  default     = "gs-paas-dih-data-examples"
}

variable "copy_sample_data" {
  type        = bool
  description = "Indicates whether to copy sample data"
  default     = false
}

variable "s3_default_sor_name" {
  type        = string
  default     = "s3_data_bucket"
  description = "System of record name for S3 bucket data source"
}

variable "default_ingress_class" {
  type        = string
  description = "Default ingress class for Data Integration Hub"
  default     = "nginx-external"
}

variable "nginx_ingress_helm_version" {
  type        = string
  description = "Version of the NGINX Ingress Helm chart"
  default     = "4.8.3"
}

variable "prometheus_helm_version" {
  type        = string
  description = "Version of the Prometheus Helm chart"
  default     = "54.2.2"
}

variable "cm_helm_version" {
  type        = string
  description = "Version of the Cert Manager Helm chart"
  default     = "1.13.2"
}

variable "autoscaler_helm_version" {
  type        = string
  description = "Version of the Kubernetes Cluster Autoscaler Helm chart"
  default     = "9.29.1"
}

variable "dih_sku_production" {
  type    = bool
  default = false
}

variable "dih_kafka_pvc_size" {
  type        = string
  default     = null
  description = "PVC size created by Kafka"
}

variable "dih_zookeeper_pvc_size" {
  type        = string
  default     = null
  description = "PVC size created by Kafka"
}

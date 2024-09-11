# Terraform Module: Gigaspaces Smart DIH Platform on AWS

[![Terraform Version](https://img.shields.io/badge/Terraform-%3E%3D1.6.5-blue.svg)](https://www.terraform.io)

<br/>

## Overview

Smart DIH installation

## Usage

This module manages the creation and configuration of the Gigaspaces Smart DIH Platform on an AWS Kubernetes Engine cluster. It sets up Node Pools, IP MASQ, Network Policies, and other necessary components. Additionally, it provisions a new VPC, EKS, and S3, and installs all required services for the platform.
  It supports customer managed VPC

```hcl
module "dih" {
  source                         = "github.com/gigaspaces/terraform-aws-smartdih"
  version                        = "~> 1.0"

  name                           = "smartdih"
  azs_count                      =  3
  cidr_block                     = "10.100.0.0/16"
  whitelist_cidrs                = ["0.0.0.0/0"]
  k8s_whitelist_cidrs            = ["0.0.0.0/0"]

  cluster_endpoint_public_access = true
  enable_public_ingress          = true
  enable_internal_ingress        = false

  dih_helm_version               = "17.0.1"
  dih_license                    = "Tryme"
  dih_enable_iidr                = false
  dih_enable_datagw              = false
  dih_sku_production             = false
  dih_security_enabled           = true

  enable_s3_buckets              = false
  enable_dih_default_space       = false
  enable_dih_oracle              = false
  enable_s3_buckets              = false
  enable_bastion                 = false

  tags = {
    Environment = dev
    project = dih
  }
}

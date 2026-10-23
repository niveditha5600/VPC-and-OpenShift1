########################################################################################################################
# Account / placement
########################################################################################################################

variable "ibmcloud_api_key" {
  type        = string
  description = "IBM Cloud API key used by the provider. Supply it with the TF_VAR_ibmcloud_api_key environment variable; never commit it."
  sensitive   = true
}

variable "region" {
  type        = string
  description = "IBM Cloud region to deploy into. The region must provide three availability zones (for example us-south, eu-de, eu-gb, jp-tok)."
  default     = "us-south"
}

variable "prefix" {
  type        = string
  description = "Prefix applied to the name of every resource created by this configuration."

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,14}[a-z0-9])?$", var.prefix))
    error_message = "The prefix must be 1-16 characters, start with a lowercase letter, end with a letter or number, and contain only lowercase letters, numbers and hyphens."
  }
}

variable "existing_resource_group_name" {
  type        = string
  description = "Name of an existing resource group to deploy into. If null, a new resource group named '<prefix>-resource-group' is created."
  default     = null
}

variable "resource_tags" {
  type        = list(string)
  description = "User tags applied to the resources that support them."
  default     = []
}

variable "access_tags" {
  type        = list(string)
  description = "Access management tags (format 'key:value') applied to the resources that support them. The tags must already exist in the account."
  default     = []
}

########################################################################################################################
# Network
########################################################################################################################

variable "vpc_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks of the worker subnets, one per availability zone, in the order zone-1, zone-2, zone-3."
  default     = ["10.10.10.0/24", "10.20.10.0/24", "10.30.10.0/24"]

  validation {
    condition     = length(var.vpc_subnet_cidrs) == 3 && alltrue([for cidr in var.vpc_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "Exactly three valid IPv4 CIDR blocks are required, one per zone."
  }

  validation {
    condition     = alltrue([for cidr in var.vpc_subnet_cidrs : can(cidrhost(cidr, 0)) && startswith(cidr, "10.")])
    error_message = "The subnet CIDR blocks must be inside 10.0.0.0/8, which is the network range the VPC ACL rules are generated for."
  }
}

variable "public_ingress_cidrs" {
  type        = list(string)
  description = "Source CIDR block allowed to reach the public load balancers on HTTP (80) and HTTPS (443). Restrict it to limit exposure of the applications. Exactly one block is supported because a VPC network ACL is limited to 25 rules."
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.public_ingress_cidrs) == 1 && alltrue([for cidr in var.public_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Provide exactly one valid IPv4 CIDR block. The network ACL holds 18 fixed rules plus 4 per ingress CIDR and is limited to 25 rules."
  }
}

########################################################################################################################
# Encryption
########################################################################################################################

variable "create_kms_authorization_policies" {
  type        = bool
  description = "Whether to create the IAM service authorizations that let Kubernetes Service and Block Storage for VPC use the Key Protect keys. Set to false only if equivalent account-wide authorizations already exist, otherwise creation fails as a duplicate."
  default     = true
}

variable "kms_force_delete" {
  type        = bool
  description = "Whether the Key Protect root keys are force-deleted on destroy. Keys that are still registered with the cluster or Object Storage cannot be deleted otherwise. Leave false for production."
  default     = false
}

########################################################################################################################
# OpenShift cluster
########################################################################################################################

variable "ocp_version" {
  type        = string
  description = "OpenShift version in the format 4.x. If null, the current IBM Cloud default version is used. The value is only used at cluster creation."
  default     = null
}

variable "ocp_entitlement" {
  type        = string
  description = "Value applied to the entitlements for OpenShift cluster provisioning, for example 'cloud_pak' when using Cloud Pak entitlement. Leave null for the standard entitlement."
  default     = null
}

variable "worker_machine_type" {
  type        = string
  description = "Flavor of the worker nodes."
  default     = "bx2.4x16"
}

variable "workers_per_zone" {
  type        = number
  description = "Number of worker nodes in each of the three zones."
  default     = 2

  validation {
    condition     = var.workers_per_zone >= 1
    error_message = "workers_per_zone must be at least 1."
  }
}

variable "worker_operating_system" {
  type        = string
  description = "Operating system of the worker nodes. RHCOS requires OpenShift 4.15 or later."
  default     = "RHCOS"

  validation {
    condition     = contains(["RHCOS", "RHEL_9_64"], var.worker_operating_system)
    error_message = "worker_operating_system must be RHCOS or RHEL_9_64."
  }
}

variable "disable_public_endpoint" {
  type        = bool
  description = "Set to true to create a private-only cluster with no public service endpoint. This cannot be changed after the cluster is created, and Terraform must then run from a host that can reach the private endpoint."
  default     = false
}

variable "disable_outbound_traffic_protection" {
  type        = bool
  description = "Set to true to allow workloads to reach the public internet, which is required for the OperatorHub in the OpenShift console. The default (false) blocks public outbound traffic from the workers."
  default     = false
}

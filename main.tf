########################################################################################################################
# Resource group
########################################################################################################################

module "resource_group" {
  source  = "terraform-ibm-modules/resource-group/ibm"
  version = "1.6.1"
  # Create a new group unless an existing one is named
  resource_group_name          = var.existing_resource_group_name == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.existing_resource_group_name
}

########################################################################################################################
# Encryption: Key Protect with one root key each for cluster secrets, worker boot volumes and the Object Storage bucket
########################################################################################################################

locals {
  ocp_key_ring    = "${var.prefix}-ocp"
  cos_key_ring    = "${var.prefix}-cos"
  cluster_key     = "${var.prefix}-cluster-data-key"
  boot_volume_key = "${var.prefix}-boot-volume-key"
  cos_key         = "${var.prefix}-cos-key"
}

module "kms" {
  source                    = "terraform-ibm-modules/kms-all-inclusive/ibm"
  version                   = "5.6.15"
  key_protect_instance_name = "${var.prefix}-kp"
  resource_group_id         = module.resource_group.resource_group_id
  region                    = var.region
  resource_tags             = var.resource_tags
  access_tags               = var.access_tags
  keys = [
    {
      key_ring_name = local.ocp_key_ring
      keys = [
        {
          key_name     = local.cluster_key
          force_delete = var.kms_force_delete
        },
        {
          key_name     = local.boot_volume_key
          force_delete = var.kms_force_delete
        }
      ]
    },
    {
      key_ring_name = local.cos_key_ring
      keys = [
        {
          key_name     = local.cos_key
          force_delete = var.kms_force_delete
        }
      ]
    }
  ]
}


########################################################################################################################
# Service authorizations that let the cluster use the Key Protect root keys.
# Kubernetes Service needs Reader plus delegation for cluster secrets; Cloud Block Storage (server-protect) needs Reader
# to encrypt the worker boot volumes. The policies are scoped to this Key Protect instance only.
########################################################################################################################

resource "ibm_iam_authorization_policy" "ocp_to_kms" {
  count                       = var.create_kms_authorization_policies ? 1 : 0
  source_service_name         = "containers-kubernetes"
  target_service_name         = "kms"
  target_resource_instance_id = module.kms.kms_guid
  roles                       = ["Reader", "Authorization Delegator"]
  description                 = "${var.prefix}: allow Kubernetes Service to use the Key Protect root keys"
}

resource "ibm_iam_authorization_policy" "block_storage_to_kms" {
  count                       = var.create_kms_authorization_policies ? 1 : 0
  source_service_name         = "server-protect"
  target_service_name         = "kms"
  target_resource_instance_id = module.kms.kms_guid
  roles                       = ["Reader"]
  description                 = "${var.prefix}: allow Block Storage for VPC to encrypt worker boot volumes with Key Protect"
}



########################################################################################################################
# Object Storage: one instance shared by the VPC flow log bucket and the OpenShift internal registry
########################################################################################################################

module "cos" {
  source                 = "terraform-ibm-modules/cos/ibm"
  version                = "11.1.4"
  cos_instance_name      = "${var.prefix}-cos"
  resource_group_id      = module.resource_group.resource_group_id
  region                 = var.region
  resource_tags          = var.resource_tags
  access_tags            = var.access_tags
  create_cos_bucket      = true
  bucket_name            = "${var.prefix}-vpc-flow-logs"
  kms_encryption_enabled = true
  kms_key_crn            = module.kms.keys["${local.cos_key_ring}.${local.cos_key}"].crn
}

########################################################################################################################
# Multi-zone VPC: one worker subnet and one public gateway in each of the three zones, restricted by network ACLs
########################################################################################################################

locals {
  # Public ingress to the VPC load balancers on HTTP and HTTPS, plus the response traffic (ACLs are stateless)
  public_ingress_acl_rules = flatten([
    for index, cidr in var.public_ingress_cidrs : [
      for port in [80, 443] : [
        {
          name            = "allow-${port}-in-${index}"
          action          = "allow"
          direction       = "inbound"
          source          = cidr
          destination     = "0.0.0.0/0"
          protocol        = "tcp"
          port_min        = port
          port_max        = port
          source_port_min = 1
          source_port_max = 65535
        },
        {
          name            = "allow-${port}-out-${index}"
          action          = "allow"
          direction       = "outbound"
          source          = "0.0.0.0/0"
          destination     = cidr
          protocol        = "tcp"
          port_min        = 1
          port_max        = 65535
          source_port_min = port
          source_port_max = port
        }
      ]
    ]
  ])

  # Instance metadata service, required by the workers when custom ACLs are used
  metadata_acl_rules = [
    {
      name            = "allow-metadata-out"
      action          = "allow"
      direction       = "outbound"
      source          = "0.0.0.0/0"
      destination     = "169.254.169.254/32"
      protocol        = null
      port_min        = null
      port_max        = null
      source_port_min = null
      source_port_max = null
    },
    {
      name            = "allow-metadata-in"
      action          = "allow"
      direction       = "inbound"
      source          = "169.254.169.254/32"
      destination     = "0.0.0.0/0"
      protocol        = null
      port_min        = null
      port_max        = null
      source_port_min = null
      source_port_max = null
    }
  ]

  # Outbound HTTP/HTTPS through the public gateways, plus the response traffic
  public_egress_acl_rules = flatten([
    for port in [80, 443] : [
      {
        name            = "allow-${port}-egress"
        action          = "allow"
        direction       = "outbound"
        source          = "0.0.0.0/0"
        destination     = "0.0.0.0/0"
        protocol        = "tcp"
        port_min        = port
        port_max        = port
        source_port_min = 1
        source_port_max = 65535
      },
      {
        name            = "allow-${port}-egress-return"
        action          = "allow"
        direction       = "inbound"
        source          = "0.0.0.0/0"
        destination     = "0.0.0.0/0"
        protocol        = "tcp"
        port_min        = 1024
        port_max        = 65535
        source_port_min = port
        source_port_max = port
      }
    ]
  ])
}

module "vpc" {
  source            = "terraform-ibm-modules/landing-zone-vpc/ibm"
  version           = "10.1.5"
  resource_group_id = module.resource_group.resource_group_id
  region            = var.region
  name              = "vpc"
  prefix            = var.prefix
  resource_tags     = var.resource_tags
  access_tags       = var.access_tags

  subnets = {
    zone-1 = [{
      name           = "subnet-a"
      cidr           = var.vpc_subnet_cidrs[0]
      public_gateway = true
      acl_name       = "vpc-acl"
    }]
    zone-2 = [{
      name           = "subnet-b"
      cidr           = var.vpc_subnet_cidrs[1]
      public_gateway = true
      acl_name       = "vpc-acl"
    }]
    zone-3 = [{
      name           = "subnet-c"
      cidr           = var.vpc_subnet_cidrs[2]
      public_gateway = true
      acl_name       = "vpc-acl"
    }]
  }

  use_public_gateways = {
    zone-1 = true
    zone-2 = true
    zone-3 = true
  }

  network_acls = [{
    name                         = "vpc-acl"
    add_ibm_cloud_internal_rules = true
    add_vpc_connectivity_rules   = true
    prepend_ibm_rules            = true
    rules                        = concat(local.metadata_acl_rules, local.public_ingress_acl_rules, local.public_egress_acl_rules)
  }]

  # Least privilege: remove the allow-all rules from the default security group and ACL
  clean_default_sg_acl = true

  # Flow logs are written to the KMS-encrypted bucket
  enable_vpc_flow_logs                   = true
  create_authorization_policy_vpc_to_cos = true
  existing_cos_instance_guid             = module.cos.cos_instance_guid
  existing_storage_bucket_name           = module.cos.bucket_name
}

########################################################################################################################
# Red Hat OpenShift (ROKS) cluster spread across the three zones
#
# IBM Cloud creates the public and private VPC load balancers for the cluster Ingress automatically. They are placed
# in the worker subnets above and secured by the IBM-managed kube-lbaas-<cluster-id> security group and the subnet ACLs.
########################################################################################################################

locals {
  # Flatten the per-zone subnet map into the list shape the cluster module expects
  cluster_subnets = flatten([
    for zone, subnets in module.vpc.subnet_detail_map : [
      for subnet in subnets : {
        id         = subnet.id
        zone       = subnet.zone
        cidr_block = subnet.cidr_block
      }
    ]
  ])

  worker_pools = [
    {
      subnet_prefix    = "default"
      pool_name        = "default" # the module requires the default pool to be named "default"
      machine_type     = var.worker_machine_type
      workers_per_zone = var.workers_per_zone
      operating_system = var.worker_operating_system
      boot_volume_encryption_kms_config = {
        crk             = module.kms.keys["${local.ocp_key_ring}.${local.boot_volume_key}"].key_id
        kms_instance_id = module.kms.kms_guid
      }
    }
  ]
}

module "ocp_base" {
  source  = "terraform-ibm-modules/base-ocp-vpc/ibm"
  version = "4.0.7"

  cluster_name      = "${var.prefix}-ocp"
  resource_group_id = module.resource_group.resource_group_id
  region            = var.region
  vpc_id            = module.vpc.vpc_id
  vpc_subnets       = { default = local.cluster_subnets }
  worker_pools      = local.worker_pools

  ocp_version                         = var.ocp_version
  ocp_entitlement                     = var.ocp_entitlement
  disable_public_endpoint             = var.disable_public_endpoint
  disable_outbound_traffic_protection = var.disable_outbound_traffic_protection

  # Reuse the shared Object Storage instance for the internal image registry
  use_existing_cos = true
  existing_cos_id  = module.cos.cos_instance_id

  # Envelope encryption of Kubernetes secrets with the customer-managed root key
  kms_config = {
    instance_id = module.kms.kms_guid
    crk_id      = module.kms.keys["${local.ocp_key_ring}.${local.cluster_key}"].key_id
  }

  resource_tags = var.resource_tags
  access_tags   = var.access_tags

  # The authorizations must exist before the cluster and worker pools reference the Key Protect keys
  depends_on = [
    ibm_iam_authorization_policy.ocp_to_kms,
    ibm_iam_authorization_policy.block_storage_to_kms,
  ]
}

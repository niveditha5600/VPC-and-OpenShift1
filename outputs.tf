output "resource_group_id" {
  description = "ID of the resource group that contains the resources."
  value       = module.resource_group.resource_group_id
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_crn" {
  description = "CRN of the VPC."
  value       = module.vpc.vpc_crn
}

output "subnet_detail_map" {
  description = "Worker subnets by zone (ID, zone, CIDR block, CRN)."
  value       = module.vpc.subnet_detail_map
}

output "public_gateways" {
  description = "Public gateway IDs by zone."
  value       = module.vpc.public_gateways
}

output "cluster_id" {
  description = "ID of the OpenShift cluster."
  value       = module.ocp_base.cluster_id
}

output "cluster_name" {
  description = "Name of the OpenShift cluster."
  value       = module.ocp_base.cluster_name
}

output "cluster_crn" {
  description = "CRN of the OpenShift cluster."
  value       = module.ocp_base.cluster_crn
}

output "ingress_hostname" {
  description = "Ingress subdomain of the cluster, served by the VPC load balancers."
  value       = module.ocp_base.ingress_hostname
}

output "public_service_endpoint_url" {
  description = "Public service endpoint URL of the cluster (empty when the public endpoint is disabled)."
  value       = module.ocp_base.public_service_endpoint_url
}

output "private_service_endpoint_url" {
  description = "Private service endpoint URL of the cluster."
  value       = module.ocp_base.private_service_endpoint_url
}

output "kms_instance_guid" {
  description = "GUID of the Key Protect instance."
  value       = module.kms.kms_guid
}

output "cos_instance_crn" {
  description = "CRN of the Object Storage instance."
  value       = module.cos.cos_instance_crn
}

output "flow_logs_bucket_name" {
  description = "Name of the bucket that receives the VPC flow logs."
  value       = module.cos.bucket_name
}

output "public_ip" {
  description = "Public IP address of the mirror instance (ARM)"
  value       = oci_core_instance.mirror.public_ip
  sensitive   = true
}

output "public_ipv6" {
  description = "Public IPv6 address of the mirror instance"
  value       = length(data.oci_core_vnic.mirror.ipv6addresses) > 0 ? data.oci_core_vnic.mirror.ipv6addresses[0] : null
  sensitive   = true
}

output "instance_ocid" {
  description = "OCID of the mirror compute instance (ARM)"
  value       = oci_core_instance.mirror.id
  sensitive   = true
}

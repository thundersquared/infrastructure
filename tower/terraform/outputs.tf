output "public_ip" {
  description = "Public IP address of the tower instance (ARM)"
  value       = oci_core_instance.tower.public_ip
  sensitive   = true
}

output "public_ipv6" {
  description = "Public IPv6 address of the tower instance"
  value       = length(data.oci_core_vnic.tower.ipv6addresses) > 0 ? data.oci_core_vnic.tower.ipv6addresses[0] : null
  sensitive   = true
}

output "instance_ocid" {
  description = "OCID of the tower compute instance (ARM)"
  value       = oci_core_instance.tower.id
  sensitive   = true
}

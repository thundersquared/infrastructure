output "public_ip" {
  description = "Public IP address of the tower instance (ARM)"
  value       = oci_core_instance.tower.public_ip
  sensitive   = true
}

output "instance_ocid" {
  description = "OCID of the tower compute instance (ARM)"
  value       = oci_core_instance.tower.id
  sensitive   = true
}

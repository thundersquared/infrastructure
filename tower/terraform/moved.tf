# Resource address renames: gateway → tower
# These blocks migrate state without destroying existing infrastructure.

moved {
  from = oci_core_instance.gateway
  to   = oci_core_instance.tower
}

moved {
  from = oci_core_vcn.gateway
  to   = oci_core_vcn.tower
}

moved {
  from = oci_core_internet_gateway.gateway
  to   = oci_core_internet_gateway.tower
}

moved {
  from = oci_core_route_table.gateway
  to   = oci_core_route_table.tower
}

moved {
  from = oci_core_security_list.gateway
  to   = oci_core_security_list.tower
}

moved {
  from = oci_core_subnet.gateway
  to   = oci_core_subnet.tower
}

# arm1.turin.oci DNS record deleted — tower.compute.eu replaces it
removed {
  from = cloudflare_dns_record.arm1

  lifecycle {
    destroy = true
  }
}

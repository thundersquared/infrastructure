resource "oci_core_vcn" "tower" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.instance_display_name}-vcn"
  dns_label      = var.instance_display_name
  is_ipv6enabled = true
}

resource "oci_core_internet_gateway" "tower" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.tower.id
  display_name   = "${var.instance_display_name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "tower" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.tower.id
  display_name   = "${var.instance_display_name}-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.tower.id
  }

  route_rules {
    destination       = "::/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.tower.id
  }
}

resource "oci_core_security_list" "tower" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.tower.id
  display_name   = "${var.instance_display_name}-sl"

  # Allow all outbound traffic (IPv4 + IPv6)
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  egress_security_rules {
    destination = "::/0"
    protocol    = "all"
    stateless   = false
  }

  # SSH
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # WireGuard
  ingress_security_rules {
    protocol  = "17" # UDP
    source    = "0.0.0.0/0"
    stateless = false

    udp_options {
      min = var.wireguard_port
      max = var.wireguard_port
    }
  }

  # ICMP type 3 (destination unreachable) — required for path MTU discovery
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false

    icmp_options {
      type = 3
      code = 4
    }
  }

  # ICMP type 8 (ping) from anywhere
  ingress_security_rules {
    protocol  = "1" # ICMP
    source    = "0.0.0.0/0"
    stateless = false

    icmp_options {
      type = 8
    }
  }

  # SSH (IPv6)
  ingress_security_rules {
    protocol  = "6" # TCP
    source    = "::/0"
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  # WireGuard (IPv6)
  ingress_security_rules {
    protocol  = "17" # UDP
    source    = "::/0"
    stateless = false

    udp_options {
      min = var.wireguard_port
      max = var.wireguard_port
    }
  }

  # ICMPv6 — required for SLAAC, path MTU discovery, and ping
  ingress_security_rules {
    protocol  = "58" # ICMPv6
    source    = "::/0"
    stateless = false
  }
}

resource "oci_core_subnet" "tower" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.tower.id
  cidr_block                 = var.subnet_cidr
  # Carve a /64 from the VCN's OCI-assigned /56
  ipv6cidr_block             = cidrsubnet(oci_core_vcn.tower.ipv6cidr_blocks[0], 8, 0)
  display_name               = "${var.instance_display_name}-subnet"
  dns_label                  = "pub"
  route_table_id             = oci_core_route_table.tower.id
  security_list_ids          = [oci_core_security_list.tower.id]
  prohibit_public_ip_on_vnic = false
}

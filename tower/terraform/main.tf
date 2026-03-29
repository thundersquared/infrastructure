# Look up the latest Ubuntu 24.04 Minimal ARM image in this region
data "oci_core_images" "ubuntu_24_04_minimal" {
  compartment_id   = var.compartment_ocid
  operating_system = "Canonical Ubuntu"
  sort_by          = "TIMECREATED"
  sort_order       = "DESC"
  state            = "AVAILABLE"

  filter {
    name   = "display_name"
    values = ["Canonical-Ubuntu-24\\.04-Minimal-aarch64.*"]
    regex  = true
  }
}

# Use first AD in the tenancy when availability_domain is not specified
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  availability_domain = var.availability_domain != null ? var.availability_domain : (
    length(data.oci_identity_availability_domains.ads.availability_domains) > 0
    ? data.oci_identity_availability_domains.ads.availability_domains[0].name
    : error("No availability domains found in tenancy — set var.availability_domain explicitly")
  )
  image_id = var.image_ocid != null ? var.image_ocid : (
    length(data.oci_core_images.ubuntu_24_04_minimal.images) > 0
    ? data.oci_core_images.ubuntu_24_04_minimal.images[0].id
    : error("No Ubuntu 24.04 Minimal ARM image found in region — set var.image_ocid explicitly")
  )
}

resource "oci_core_instance" "tower" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = var.instance_display_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  source_details {
    source_type             = "image"
    source_id               = local.image_id
    boot_volume_size_in_gbs = 100
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.tower.id
    display_name     = "${var.instance_display_name}-vnic"
    assign_public_ip = true
    assign_ipv6ip    = true
    hostname_label   = var.instance_display_name
  }

  metadata = {
    ssh_authorized_keys = join("\n", var.ssh_authorized_keys)
  }

  # platform_config for AMPERE_FLEXIBLE (Secure Boot, TPM, Measured Boot) is not
  # supported in oracle/oci provider 8.7.0 — type is missing from schema validation.
  # Enable via OCI Console: stop instance → Edit → Security → enable → start.

  agent_config {
    plugins_config {
      name          = "Block Volume Management"
      desired_state = "ENABLED"
    }
    plugins_config {
      name          = "Management Agent"
      desired_state = "ENABLED"
    }
  }

  # This instance is never destroyed by OpenTofu
  lifecycle {
    prevent_destroy = true
    # Ignore image changes so upgrades don't trigger replace
    ignore_changes = [source_details[0].source_id]
  }
}

data "oci_core_vnic_attachments" "tower" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.tower.id
}

data "oci_core_vnic" "tower" {
  vnic_id = data.oci_core_vnic_attachments.tower.vnic_attachments[0].vnic_id
}

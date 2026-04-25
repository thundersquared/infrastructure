terraform {
  required_version = "~> 1.11"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "8.11.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.19.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key  = var.private_key
  region       = var.region
}

terraform {
  required_version = "1.13.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "9.7.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.26.0"
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

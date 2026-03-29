variable "tenancy_ocid" {
  description = "OCID of the OCI tenancy"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCID of the OCI user for API authentication"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "Fingerprint of the OCI API key"
  type        = string
  sensitive   = true
}

variable "private_key" {
  description = "PEM-encoded OCI API private key (full content)"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "OCI region identifier (e.g. eu-frankfurt-1)"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources are created (root compartment = tenancy OCID)"
  type        = string
}

variable "availability_domain" {
  description = "Availability domain name (e.g. Uocm:EU-FRANKFURT-1-AD-1). Find with: oci iam availability-domain list"
  type        = string
  default     = ""
}

variable "ssh_authorized_keys" {
  description = "List of SSH public keys to inject into the instance for the ubuntu user"
  type        = list(string)
  sensitive   = true
}

variable "instance_display_name" {
  description = "Display name for the compute instance"
  type        = string
  default     = "tower"
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "wireguard_port" {
  description = "UDP port for WireGuard"
  type        = number
  default     = 51820
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions for the target zone"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for sqrd-dns.com"
  type        = string
}

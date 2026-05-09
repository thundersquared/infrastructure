provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_dns_record" "mirror" {
  zone_id = var.cloudflare_zone_id
  name    = "mirror.eu"
  type    = "A"
  content = oci_core_instance.mirror.public_ip
  ttl     = 3600
  proxied = false
}

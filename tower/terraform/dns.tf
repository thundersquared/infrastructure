provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_dns_record" "tower" {
  zone_id = var.cloudflare_zone_id
  name    = "tower.compute.eu"
  type    = "A"
  content = oci_core_instance.tower.public_ip
  ttl     = 3600
  proxied = false
}

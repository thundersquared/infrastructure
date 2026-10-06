provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_dns_record" "tower" {
  zone_id = var.cloudflare_zone_id
  name    = var.tower_hostname
  type    = "A"
  content = oci_core_instance.tower.public_ip
  ttl     = 3600
  proxied = false
}

# The VNIC is created with an IPv6 address (assign_ipv6ip in main.tf); publish
# it once OCI reports one, so clients can reach Headscale, DERP and STUN over
# IPv6 too.
resource "cloudflare_dns_record" "tower_aaaa" {
  count = length(data.oci_core_vnic.tower.ipv6addresses) > 0 ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.tower_hostname
  type    = "AAAA"
  content = data.oci_core_vnic.tower.ipv6addresses[0]
  ttl     = 3600
  proxied = false
}

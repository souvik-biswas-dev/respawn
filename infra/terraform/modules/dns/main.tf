resource "cloudflare_record" "a" {
  count = var.enabled ? 1 : 0

  zone_id = var.zone_id
  name    = var.record_name
  type    = "A"
  content = var.ipv4_address
  ttl     = var.ttl
  # Not proxied: the drills must reach the real server, and k3s terminates TLS itself.
  proxied = false
  comment = "managed by respawn terraform"

  lifecycle {
    precondition {
      condition     = var.zone_id != ""
      error_message = "dns is enabled but zone_id is empty. Set cloudflare_zone_id or disable dns."
    }
  }
}

resource "cloudflare_record" "aaaa" {
  count = var.enabled && var.ipv6_address != "" ? 1 : 0

  zone_id = var.zone_id
  name    = var.record_name
  type    = "AAAA"
  content = var.ipv6_address
  ttl     = var.ttl
  proxied = false
  comment = "managed by respawn terraform"
}

# Hetzner firewalls are default-deny for inbound traffic once any rule exists,
# so only the ports listed here are reachable. Outbound is unrestricted.
resource "hcloud_firewall" "this" {
  name   = var.name
  labels = merge(var.labels, { app = "respawn" })

  rule {
    description = "ssh from admin addresses only"
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = var.ssh_allowed_cidrs
  }

  rule {
    description = "http (ingress and certificate challenges)"
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "https"
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }

  rule {
    description = "kubernetes api from admin addresses only"
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = var.kube_api_allowed_cidrs
  }

  dynamic "apply_to" {
    for_each = var.server_ids
    content {
      server = apply_to.value
    }
  }
}

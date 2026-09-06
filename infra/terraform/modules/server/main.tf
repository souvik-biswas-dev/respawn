locals {
  labels = merge(var.labels, { app = "respawn" })
}

# Registering the key with Hetzner stops it from emailing a root password.
resource "hcloud_ssh_key" "ops" {
  name       = "${var.name}-ops"
  public_key = var.ssh_public_key
  labels     = local.labels
}

resource "hcloud_server" "this" {
  name        = var.name
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.ops.id]
  labels      = local.labels

  delete_protection  = var.delete_protection
  rebuild_protection = var.delete_protection

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    ops_username   = var.ops_username
    ssh_public_key = var.ssh_public_key
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    # cloud-init only runs on first boot. Without this, editing it would force
    # a destroy/recreate of a server that is already running and holds data.
    ignore_changes = [user_data, image]
  }
}

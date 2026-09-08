provider "hcloud" {
  # null means "read HCLOUD_TOKEN from the environment".
  token = var.hcloud_token
}

locals {
  # The Cloudflare provider checks the token format even when no DNS resource
  # exists, which would break plan for people without a domain. A well-formed
  # dummy is used only when DNS is disabled, so it never reaches the API.
  cloudflare_token = var.enable_dns ? var.cloudflare_api_token : "dns-disabled-placeholder-token-000000000"
}

provider "cloudflare" {
  api_token = local.cloudflare_token
}

module "server" {
  source = "../../modules/server"

  name              = var.name
  location          = var.location
  server_type       = var.server_type
  image             = var.image
  ssh_public_key    = var.ssh_public_key
  ops_username      = var.ops_username
  delete_protection = var.delete_protection
}

module "firewall" {
  source = "../../modules/firewall"

  name                   = "${var.name}-fw"
  server_ids             = [module.server.id]
  ssh_allowed_cidrs      = var.ssh_allowed_cidrs
  kube_api_allowed_cidrs = var.kube_api_allowed_cidrs
}

module "dns" {
  source = "../../modules/dns"

  enabled      = var.enable_dns
  zone_id      = var.cloudflare_zone_id
  record_name  = var.dns_record_name
  ipv4_address = module.server.ipv4_address
  ipv6_address = module.server.ipv6_address
}

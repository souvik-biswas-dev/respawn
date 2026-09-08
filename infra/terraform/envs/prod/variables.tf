# ---- provider credentials -------------------------------------------------
variable "hcloud_token" {
  description = "Hetzner Cloud API token. Prefer the HCLOUD_TOKEN env var; leave null here."
  type        = string
  default     = null
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit). Prefer TF_VAR_cloudflare_api_token. Only needed when enable_dns is true."
  type        = string
  default     = null
  sensitive   = true
}

# ---- server ---------------------------------------------------------------
variable "name" {
  description = "Base name for all resources."
  type        = string
  default     = "respawn"
}

variable "location" {
  description = "Hetzner location code (nbg1, fsn1, hel1, ash, hil)."
  type        = string
  default     = "nbg1"
}

variable "server_type" {
  description = "Hetzner server type. Check `hcloud server-type list` for names and prices before applying."
  type        = string
  default     = "cx22"
}

variable "image" {
  description = "OS image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key" {
  description = "Your PUBLIC ssh key, one line. Find it with: cat ~/.ssh/id_ed25519.pub"
  type        = string
}

variable "ops_username" {
  description = "Admin user created on the server."
  type        = string
  default     = "ops"
}

variable "delete_protection" {
  description = "Protect the server from deletion. Turn off before running the delete-server drill."
  type        = bool
  default     = false
}

# ---- firewall -------------------------------------------------------------
variable "ssh_allowed_cidrs" {
  description = "Who may SSH in. Your public IP as /32, e.g. [\"203.0.113.10/32\"]. Open-to-all is rejected."
  type        = list(string)
}

variable "kube_api_allowed_cidrs" {
  description = "Who may reach the Kubernetes API on 6443. Usually the same as ssh_allowed_cidrs."
  type        = list(string)
}

# ---- dns (optional) -------------------------------------------------------
variable "enable_dns" {
  description = "Create Cloudflare DNS records. Leave false if you have no domain."
  type        = bool
  default     = false
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID. Required when enable_dns is true."
  type        = string
  default     = ""
}

variable "dns_record_name" {
  description = "Record name inside the zone."
  type        = string
  default     = "respawn"
}

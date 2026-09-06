variable "enabled" {
  description = "Create DNS records. Set false to skip DNS entirely (no domain needed)."
  type        = bool
  default     = false
}

variable "zone_id" {
  description = "Cloudflare zone ID of the domain. Required when enabled."
  type        = string
  default     = ""
}

variable "record_name" {
  description = "Record name inside the zone, e.g. 'respawn' for respawn.example.com, or '@' for the apex."
  type        = string
  default     = "respawn"
}

variable "ipv4_address" {
  description = "IPv4 address for the A record."
  type        = string
}

variable "ipv6_address" {
  description = "IPv6 address for the AAAA record. Empty string skips the record."
  type        = string
  default     = ""
}

variable "ttl" {
  description = "TTL in seconds. Kept short so a rebuilt server is reachable quickly."
  type        = number
  default     = 120
}

variable "name" {
  description = "Server name. Also used as the prefix for related resources."
  type        = string
}

variable "location" {
  description = "Hetzner location code, e.g. nbg1, fsn1, hel1, ash, hil."
  type        = string
}

variable "server_type" {
  description = "Hetzner server type. Names change over time: list current ones with `hcloud server-type list`."
  type        = string
}

variable "image" {
  description = "OS image name."
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key" {
  description = "Public SSH key (one line, e.g. 'ssh-ed25519 AAAA... you@host'). Never a private key."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) ", var.ssh_public_key))
    error_message = "ssh_public_key must be a public key line starting with ssh-ed25519, ssh-rsa or ecdsa-sha2-."
  }
}

variable "ops_username" {
  description = "Non-root admin user created by cloud-init."
  type        = string
  default     = "ops"
}

variable "delete_protection" {
  description = "Block accidental deletion in the Hetzner API. Must be false for the delete-server drill."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Extra labels applied to the server and SSH key."
  type        = map(string)
  default     = {}
}

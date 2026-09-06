variable "name" {
  description = "Firewall name."
  type        = string
}

variable "server_ids" {
  description = "IDs of servers the firewall is attached to."
  type        = list(number)
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to reach SSH (22). Use your own IP, e.g. 203.0.113.10/32."
  type        = list(string)

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && !contains(var.ssh_allowed_cidrs, "0.0.0.0/0") && !contains(var.ssh_allowed_cidrs, "::/0")
    error_message = "ssh_allowed_cidrs must be non-empty and must not be open to the whole internet."
  }
}

variable "kube_api_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API (6443)."
  type        = list(string)

  validation {
    condition     = length(var.kube_api_allowed_cidrs) > 0 && !contains(var.kube_api_allowed_cidrs, "0.0.0.0/0") && !contains(var.kube_api_allowed_cidrs, "::/0")
    error_message = "kube_api_allowed_cidrs must be non-empty and must not be open to the whole internet."
  }
}

variable "labels" {
  description = "Labels applied to the firewall."
  type        = map(string)
  default     = {}
}

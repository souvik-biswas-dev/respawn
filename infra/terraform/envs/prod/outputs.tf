output "server_name" {
  description = "Server name."
  value       = module.server.name
}

output "server_ip" {
  description = "Public IPv4 address of the server."
  value       = module.server.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6 address of the server."
  value       = module.server.ipv6_address
}

output "ssh_command" {
  description = "Command to log in as the ops user."
  value       = "ssh ${var.ops_username}@${module.server.ipv4_address}"
}

output "dns_hostname" {
  description = "DNS name pointing at the server, or null when DNS is disabled."
  value       = module.dns.hostname
}

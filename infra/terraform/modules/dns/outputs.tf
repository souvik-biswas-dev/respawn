output "hostname" {
  description = "Fully qualified record name, or null when DNS is disabled."
  value       = var.enabled ? cloudflare_record.a[0].hostname : null
}

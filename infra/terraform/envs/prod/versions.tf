terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.52"
    }
  }

  # Remote state (optional). Local state is fine for a demo, but if the laptop
  # holding terraform.tfstate dies, so does your map of what exists. A rebuild
  # platform should not have that weakness. Any S3-compatible bucket works
  # (Hetzner Object Storage, Cloudflare R2, MinIO). Uncomment and fill in, then
  # run `terraform init -migrate-state`. Keep credentials in env vars
  # (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY), never in this file.
  #
  # backend "s3" {
  #   bucket                      = "respawn-tfstate"
  #   key                         = "prod/terraform.tfstate"
  #   region                      = "eu-central-1"
  #   endpoint                    = "https://<your-s3-endpoint>"
  #   skip_credentials_validation = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   use_path_style              = true
  # }
}

terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket = "bakseter-homelab-tofu-state"
    key    = "core/terraform.tfstate"
    region = "hel1"

    endpoints = {
      s3 = "https://hel1.your-objectstorage.com"
    }

    use_path_style = false

    use_lockfile     = true
    skip_s3_checksum = true

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}

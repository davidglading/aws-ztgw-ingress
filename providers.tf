provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = var.name_prefix, ManagedBy = "Terraform" }
  }
}

provider "ztc" {
  # In CI, set these env vars instead of hardcoding. The first three are required,
  # the fourth is optional and only used to target a non-production Zidentity environment.
  #   ZSCALER_CLIENT_ID       (required)
  #   ZSCALER_CLIENT_SECRET   (required; or ZSCALER_PRIVATE_KEY)
  #   ZSCALER_VANITY_DOMAIN   (required)
  #   ZSCALER_CLOUD           (optional — only set for non-prod, e.g. "beta")
  client_id         = var.ztc_client_id
  client_secret     = var.ztc_private_key != null && var.ztc_private_key != "" ? null : var.ztc_client_secret
  private_key       = var.ztc_private_key != null && var.ztc_private_key != "" ? var.ztc_private_key : null
  vanity_domain     = var.ztc_vanity_domain
  zscaler_cloud     = var.zscaler_cloud
  use_legacy_client = false
}

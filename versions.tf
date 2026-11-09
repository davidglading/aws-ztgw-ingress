terraform {
  required_version = ">= 1.5.0"
  required_providers {
    ztc = { source = "zscaler/ztc", version = "= 0.1.9" }
    aws = { source = "hashicorp/aws", version = "= 5.100.0" }
  }
}

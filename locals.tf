locals {
  # ZTC represents any source with no source-IP filter, rather than IPv4 /0.
  # AWS security groups continue to use allowed_client_cidrs unchanged.
  ztc_source_ips = contains(var.allowed_client_cidrs, "0.0.0.0/0") ? toset([]) : var.allowed_client_cidrs

  destination_cidrs = toset([for key in sort(keys(local.az_slots)) : local.az_slots[key].alb_cidr])
  supported_azs     = sort(tolist(setintersection(toset(data.aws_availability_zones.available.names), toset(data.aws_vpc_endpoint_service.ztgw.availability_zones))))
  selected_azs      = length(var.availability_zones) > 0 ? var.availability_zones : slice(local.supported_azs, 0, min(2, length(local.supported_azs)))
  az_slots = {
    for index, az in local.selected_azs : "az${index + 1}" => {
      az              = az
      alb_cidr        = cidrsubnet(var.vpc_cidr, 3, index)
      inspection_cidr = cidrsubnet(var.vpc_cidr, 4, 4 + index)
      web_cidr        = cidrsubnet(var.vpc_cidr, 3, 4 + index)
    }
  }
  web_slots = { for key, slot in local.az_slots : key => slot if index(sort(keys(local.az_slots)), key) < var.web_instance_count }
}

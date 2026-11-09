data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}
data "aws_vpc_endpoint_service" "ztgw" {
  service_name = var.ztgw_endpoint_service_name
}
resource "terraform_data" "requirements" {
  input = local.selected_azs
  lifecycle {
    precondition {
      condition     = length(local.selected_azs) == 2 && alltrue([for az in local.selected_azs : contains(local.supported_azs, az)])
      error_message = "The lab requires two available standard AZs supported by the existing ZTGW endpoint service."
    }
    precondition {
      condition     = data.aws_vpc_endpoint_service.ztgw.service_type == "GatewayLoadBalancer" && can(regex("\\.vpce\\.${var.aws_region}\\.", var.ztgw_endpoint_service_name))
      error_message = "Select a GatewayLoadBalancer service in aws_region, rather than an interface endpoint service or a service in another region."
    }
  }
}
resource "aws_vpc" "web" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-web" }
  depends_on           = [terraform_data.requirements]
}
resource "aws_internet_gateway" "web" {
  vpc_id = aws_vpc.web.id
  tags   = { Name = "${var.name_prefix}-igw" }
}
resource "aws_subnet" "alb" {
  for_each                = local.az_slots
  vpc_id                  = aws_vpc.web.id
  availability_zone       = each.value.az
  cidr_block              = each.value.alb_cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-alb-${each.key}", Tier = "inspected-alb" }
}
resource "aws_subnet" "inspection" {
  for_each                = local.az_slots
  vpc_id                  = aws_vpc.web.id
  availability_zone       = each.value.az
  cidr_block              = each.value.inspection_cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-gwlbe-${each.key}", Tier = "inspection" }
}
resource "aws_subnet" "web" {
  for_each                = local.az_slots
  vpc_id                  = aws_vpc.web.id
  availability_zone       = each.value.az
  cidr_block              = each.value.web_cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-web-${each.key}", Tier = "private-web" }
}
resource "aws_vpc_endpoint" "ztgw" {
  for_each          = local.az_slots
  vpc_id            = aws_vpc.web.id
  service_name      = var.ztgw_endpoint_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.inspection[each.key].id]
  tags              = { Name = "${var.name_prefix}-ztgw-${each.key}" }
}

# Inbound: IGW -> per-AZ GWLBe -> ALB. Destinations are ALB subnet CIDRs,
# not 0.0.0.0/0: AWS gateway route tables only accept VPC/subnet CIDRs.
resource "aws_route_table" "igw_ingress" {
  vpc_id = aws_vpc.web.id
  tags   = { Name = "${var.name_prefix}-igw-ingress" }
}
resource "aws_route" "ingress_inspection" {
  for_each               = local.az_slots
  route_table_id         = aws_route_table.igw_ingress.id
  destination_cidr_block = each.value.alb_cidr
  vpc_endpoint_id        = aws_vpc_endpoint.ztgw[each.key].id
}
resource "aws_route_table_association" "igw_ingress" {
  gateway_id     = aws_internet_gateway.web.id
  route_table_id = aws_route_table.igw_ingress.id
  depends_on     = [aws_route.ingress_inspection]
}

# Return: ALB -> SAME AZ GWLBe -> IGW. The endpoint's local route delivers
# inspected inbound packets to the ALB without sending them through a loop.
resource "aws_route_table" "alb" {
  for_each = local.az_slots
  vpc_id   = aws_vpc.web.id
  tags     = { Name = "${var.name_prefix}-alb-${each.key}" }
}
resource "aws_route" "alb_return_inspection" {
  for_each               = local.az_slots
  route_table_id         = aws_route_table.alb[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.ztgw[each.key].id
}
resource "aws_route_table_association" "alb" {
  for_each       = local.az_slots
  subnet_id      = aws_subnet.alb[each.key].id
  route_table_id = aws_route_table.alb[each.key].id
}
resource "aws_route_table" "inspection" {
  for_each = local.az_slots
  vpc_id   = aws_vpc.web.id
  tags     = { Name = "${var.name_prefix}-inspection-${each.key}" }
}
resource "aws_route" "inspection_internet" {
  for_each               = local.az_slots
  route_table_id         = aws_route_table.inspection[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.web.id
}
resource "aws_route_table_association" "inspection" {
  for_each       = local.az_slots
  subnet_id      = aws_subnet.inspection[each.key].id
  route_table_id = aws_route_table.inspection[each.key].id
}
# Backend/health-check traffic stays local. The website bootstraps offline;
# these private subnets have no default route, NAT, public addresses or SSH.
resource "aws_route_table" "web" {
  vpc_id = aws_vpc.web.id
  tags   = { Name = "${var.name_prefix}-private-web" }
}
resource "aws_route_table_association" "web" {
  for_each       = local.az_slots
  subnet_id      = aws_subnet.web[each.key].id
  route_table_id = aws_route_table.web.id
}

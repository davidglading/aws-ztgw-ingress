
mock_provider "ztc" {
  # v0.1.9 marks location.id Optional, not Computed. Mocks leave it null;
  # compare the rule wiring to the lookup. Real ID resolution needs a tenant.
  mock_data "ztc_location_management" {}
  mock_data "ztc_network_services" { defaults = { id = 202 } }
  mock_resource "ztc_traffic_forwarding_rule" { defaults = { id = "303", rule_id = 303 } }
}

mock_provider "aws" {
  mock_data "aws_availability_zones" { defaults = { names = ["us-west-1a", "us-west-1b", "us-west-1c"] } }
  mock_data "aws_vpc_endpoint_service" { defaults = { availability_zones = ["us-west-1b", "us-west-1c"], service_type = "GatewayLoadBalancer" } }
  mock_data "aws_ami" { defaults = { id = "ami-0123456789abcdef0" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_resource "aws_vpc" { defaults = { id = "vpc-0123456789abcdef0" } }
  mock_resource "aws_subnet" { defaults = { id = "subnet-0123456789abcdef0" } }
  mock_resource "aws_vpc_endpoint" { defaults = { id = "vpce-0123456789abcdef0" } }
  mock_resource "aws_route_table" { defaults = { id = "rtb-0123456789abcdef0" } }
  mock_resource "aws_internet_gateway" { defaults = { id = "igw-0123456789abcdef0" } }
  mock_resource "aws_security_group" { defaults = { id = "sg-0123456789abcdef0" } }
  mock_resource "aws_iam_instance_profile" { defaults = { name = "lab-ssm-profile" } }
  mock_resource "aws_lb" { defaults = { arn = "arn:aws:elasticloadbalancing:us-west-1:123456789012:loadbalancer/app/lab/0123456789abcdef", dns_name = "lab.example.com" } }
  mock_resource "aws_lb_target_group" { defaults = { arn = "arn:aws:elasticloadbalancing:us-west-1:123456789012:targetgroup/lab/0123456789abcdef" } }
  mock_resource "aws_instance" { defaults = { id = "i-0123456789abcdef0", private_ip = "10.10.11.130" } }
}
variables {
  aws_region         = "us-west-1"
  vpc_cidr           = "10.10.11.0/24"
  availability_zones = []
  web_instance_count = 1
  enable_ssm         = true
  rule_order         = 1
  rule_rank          = 7

  name_prefix                = "ingress-test"
  enable_policy_activation   = true
  ztgw_endpoint_service_name = "com.amazonaws.vpce.us-west-1.vpce-svc-0123456789abcdef0"
  ztgw_location_name         = "existing-lab-location"
}

run "inspected_ingress_and_symmetric_return" {
  command = apply

  override_resource {
    target = aws_vpc_endpoint.ztgw["az1"]
    values = { id = "vpce-00000000000000001" }
  }
  override_resource {
    target = aws_vpc_endpoint.ztgw["az2"]
    values = { id = "vpce-00000000000000002" }
  }

  assert {
    condition     = local.selected_azs == tolist(["us-west-1b", "us-west-1c"]) && length(aws_vpc_endpoint.ztgw) == 2 && length(aws_subnet.web) == 2
    error_message = "Discover two account AZs supported by the existing GWLB service."
  }
  assert {
    condition     = alltrue([for key, slot in local.az_slots : aws_route.ingress_inspection[key].destination_cidr_block == slot.alb_cidr && aws_route.ingress_inspection[key].vpc_endpoint_id == aws_vpc_endpoint.ztgw[key].id && aws_route.alb_return_inspection[key].vpc_endpoint_id == aws_vpc_endpoint.ztgw[key].id]) && aws_vpc_endpoint.ztgw["az1"].id != aws_vpc_endpoint.ztgw["az2"].id
    error_message = "Ingress ALB routes and return routes must use the same distinct AZ endpoint."
  }
  assert {
    condition     = aws_route_table_association.igw_ingress.gateway_id == aws_internet_gateway.web.id && alltrue([for key in keys(local.az_slots) : aws_route.inspection_internet[key].destination_cidr_block == "0.0.0.0/0" && aws_route.inspection_internet[key].gateway_id == aws_internet_gateway.web.id])
    error_message = "Associate the ingress table with the IGW and route inspected responses back to the IGW."
  }
  assert {
    condition     = !aws_lb.web.internal && aws_lb.web.load_balancer_type == "application" && aws_lb_listener.http.port == 80 && aws_lb_target_group.web.port == 80 && length(aws_instance.web) == 1
    error_message = "Provide an internet-facing HTTP ALB with one private web instance by default."
  }
  assert {
    condition     = alltrue([for instance in aws_instance.web : !instance.associate_public_ip_address && instance.metadata_options[0].http_tokens == "required" && instance.root_block_device[0].encrypted]) && alltrue([for subnet in aws_subnet.web : !subnet.map_public_ip_on_launch])
    error_message = "Web instances must remain private with IMDSv2 and encrypted root disks."
  }
  assert {
    condition     = length(aws_security_group.web.ingress) == 1 && alltrue([for rule in aws_security_group.web.ingress : rule.from_port == 80 && rule.to_port == 80 && rule.security_groups == toset([aws_security_group.alb.id])])
    error_message = "Backend HTTP must be allowed only from the ALB security group."
  }
  assert {
    condition     = length(aws_vpc_endpoint.ssm) == 2 && length(aws_iam_instance_profile.ssm) == 1 && output.ztc_ingress_configuration.destination_cidrs == ["10.10.11.0/27", "10.10.11.32/27"]
    error_message = "Export private ALB destinations and provide optional private SSM access."
  }
}
run "two_web_instances_without_ssm" {
  command = apply
  variables {
    web_instance_count   = 2
    enable_ssm           = false
    allowed_client_cidrs = ["198.51.100.10/32"]
  }

  override_resource {
    target = aws_vpc_endpoint.ztgw["az1"]
    values = { id = "vpce-00000000000000001" }
  }
  override_resource {
    target = aws_vpc_endpoint.ztgw["az2"]
    values = { id = "vpce-00000000000000002" }
  }

  assert {
    condition     = length(aws_instance.web) == 2 && length(aws_lb_target_group_attachment.web) == 2 && length(aws_vpc_endpoint.ssm) == 0 && length(aws_iam_role.ssm) == 0
    error_message = "Support two private backends with management resources disabled."
  }
  assert {
    condition     = alltrue([for rule in aws_security_group.alb.ingress : toset(rule.cidr_blocks) == toset(["198.51.100.10/32"])])
    error_message = "Restrict ingress to the configured client CIDRs."
  }
}
run "custom_region_and_cidr" {
  command = plan
  variables {
    aws_region                 = "eu-west-1"
    vpc_cidr                   = "10.50.0.0/16"
    ztgw_endpoint_service_name = "com.amazonaws.vpce.eu-west-1.vpce-svc-0123456789abcdef0"
    availability_zones         = ["eu-west-1a", "eu-west-1b"]
  }
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["eu-west-1a", "eu-west-1b"] }
  }
  override_data {
    target = data.aws_vpc_endpoint_service.ztgw
    values = { availability_zones = ["eu-west-1a", "eu-west-1b"], service_type = "GatewayLoadBalancer" }
  }
  assert {
    condition     = local.az_slots["az1"].alb_cidr == "10.50.0.0/19" && local.az_slots["az1"].web_cidr == "10.50.128.0/19" && local.az_slots["az2"].az == "eu-west-1b"
    error_message = "Derive addresses and AZs from inputs rather than hard-coded default regions."
  }
}
run "reject_wrong_service_region" {
  command = plan
  variables { aws_region = "us-east-1" }
  expect_failures = [terraform_data.requirements]
}
run "reject_interface_service" {
  command = plan
  override_data {
    target = data.aws_vpc_endpoint_service.ztgw
    values = { availability_zones = ["us-west-1b", "us-west-1c"], service_type = "Interface" }
  }
  expect_failures = [terraform_data.requirements]
}
run "reject_unsupported_az" {
  command = plan
  variables { availability_zones = ["us-west-1a", "us-west-1b"] }
  expect_failures = [terraform_data.requirements]
}
run "reject_too_small_vpc" {
  command = plan
  variables { vpc_cidr = "10.10.11.0/28" }
  expect_failures = [var.vpc_cidr]
}

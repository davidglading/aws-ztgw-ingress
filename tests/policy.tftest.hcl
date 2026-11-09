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


mock_provider "ztc" {
  # v0.1.9 marks location.id Optional, not Computed. Mocks leave it null;
  # compare the rule wiring to the lookup. Real ID resolution needs a tenant.
  mock_data "ztc_location_management" {}
  mock_data "ztc_network_services" { defaults = { id = 202 } }
  mock_resource "ztc_traffic_forwarding_rule" { defaults = { id = "303", rule_id = 303 } }
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
  ztgw_location_name         = "existing-lab-location"
  allowed_client_cidrs       = ["198.51.100.10/32"]
  ztgw_endpoint_service_name = "com.amazonaws.vpce.us-west-1.vpce-svc-0123456789abcdef0"
  enable_policy_activation   = false
}
run "scoped_http_allow_then_drop" {
  command = apply
  assert {
    condition     = ztc_traffic_forwarding_rule.allow_ingress_http.forward_method == "LOCAL_SWITCH" && ztc_traffic_forwarding_rule.allow_ingress_http.order + 1 == ztc_traffic_forwarding_rule.drop_other_ingress.order && ztc_traffic_forwarding_rule.drop_other_ingress.forward_method == "DROP"
    error_message = "Allow local HTTP before the scoped catch-all DROP rule."
  }
  assert {
    condition     = ztc_traffic_forwarding_rule.allow_ingress_http.src_ips == toset(["198.51.100.10/32"]) && ztc_traffic_forwarding_rule.allow_ingress_http.dest_addresses == local.destination_cidrs && ztc_traffic_forwarding_rule.drop_other_ingress.dest_addresses == local.destination_cidrs && one(ztc_traffic_forwarding_rule.allow_ingress_http.locations).id == toset([data.ztc_location_management.existing.id]) && one(ztc_traffic_forwarding_rule.allow_ingress_http.nw_services).id == toset([202])
    error_message = "Scope policy to configured clients, private ALB subnets, existing location, and HTTP service."
  }
  assert {
    condition     = length(coalesce(ztc_traffic_forwarding_rule.drop_other_ingress.src_ips, toset([]))) == 0
    error_message = "DROP must match any source without an explicit /0 source range."
  }
  assert {
    condition     = length(ztc_activation_status.this) == 0 && !output.activation_requested
    error_message = "Disabling activation must leave the rules as drafts for manual activation."
  }
}
run "activation_after_managed_rules" {
  command = apply
  variables {
    enable_policy_activation = true
    rule_order               = 5
  }
  assert {
    condition     = length(ztc_activation_status.this) == 1 && terraform_data.policy_revision[0].input.order == 5 && terraform_data.policy_revision[0].input.destinations == local.destination_cidrs && ztc_traffic_forwarding_rule.drop_other_ingress.order == 6
    error_message = "Activation must track configured policy and preserve allow/drop ordering."
  }
}
run "reject_zero_rule_order" {
  command = plan
  variables { rule_order = 0 }
  expect_failures = [var.rule_order]
}

run "integrated_policy_uses_aws_inputs_and_activation" {
  command = apply
  variables {
    enable_policy_activation = true
    vpc_cidr                 = "10.50.0.0/16"
    allowed_client_cidrs     = ["203.0.113.20/32"]
  }
  assert {
    condition     = ztc_traffic_forwarding_rule.allow_ingress_http.dest_addresses == toset([for subnet in aws_subnet.alb : subnet.cidr_block]) && ztc_traffic_forwarding_rule.drop_other_ingress.dest_addresses == toset(["10.50.0.0/19", "10.50.32.0/19"])
    error_message = "Both rules must use the ALB subnet CIDRs from the same root configuration."
  }
  assert {
    condition     = ztc_traffic_forwarding_rule.allow_ingress_http.src_ips == var.allowed_client_cidrs && length(ztc_activation_status.this) == 1 && output.activation_requested
    error_message = "The combined apply must use the root client allowlist and request activation."
  }
}

run "any_source_uses_no_ztc_ip_filter" {
  command = apply
  variables {
    allowed_client_cidrs     = ["0.0.0.0/0", "198.51.100.10/32"]
    enable_policy_activation = true
  }
  assert {
    condition     = length(ztc_traffic_forwarding_rule.allow_ingress_http.src_ips) == 0 && length(coalesce(ztc_traffic_forwarding_rule.drop_other_ingress.src_ips, toset([]))) == 0 && length(terraform_data.policy_revision[0].input.sources) == 0
    error_message = "Any source must omit the ZTC source-IP filter, including when /0 accompanies narrower CIDRs."
  }
  assert {
    condition     = alltrue([for rule in aws_security_group.alb.ingress : toset(rule.cidr_blocks) == var.allowed_client_cidrs]) && ztc_traffic_forwarding_rule.drop_other_ingress.dest_addresses == local.destination_cidrs && one(ztc_traffic_forwarding_rule.drop_other_ingress.locations).id == toset([data.ztc_location_management.existing.id])
    error_message = "Keep AWS CIDRs unchanged and preserve DROP destination/location scope."
  }
}

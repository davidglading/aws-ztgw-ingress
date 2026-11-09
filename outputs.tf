output "website_url" {
  description = "Use this public HTTP URL after activating the ZTC ingress policy."
  value       = "http://${aws_lb.web.dns_name}"
}
output "vpc_id" { value = aws_vpc.web.id }
output "web_instances" {
  value = { for key, instance in aws_instance.web : key => { id = instance.id, private_ip = instance.private_ip } }
}
output "ztgw_endpoint_ids" { value = { for key, endpoint in aws_vpc_endpoint.ztgw : key => endpoint.id } }
output "route_table_ids" {
  value = {
    igw_ingress = aws_route_table.igw_ingress.id
    alb         = { for key, table in aws_route_table.alb : key => table.id }
    inspection  = { for key, table in aws_route_table.inspection : key => table.id }
    private_web = aws_route_table.web.id
  }
}
output "ztc_ingress_configuration" {
  description = "Inputs used by the integrated Zscaler policy. Contains no credentials."
  value = {
    name_prefix          = var.name_prefix
    ztgw_location_name   = var.ztgw_location_name
    allowed_client_cidrs = sort(tolist(var.allowed_client_cidrs))
    destination_cidrs    = [for key in sort(keys(local.az_slots)) : local.az_slots[key].alb_cidr]
  }
}

output "rule_ids" {
  value = { allow_http = ztc_traffic_forwarding_rule.allow_ingress_http.rule_id, drop_other = ztc_traffic_forwarding_rule.drop_other_ingress.rule_id }
}
output "activation_requested" { value = var.enable_policy_activation }

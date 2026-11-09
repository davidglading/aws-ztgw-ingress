data "ztc_location_management" "existing" { name = var.ztgw_location_name }
data "ztc_network_services" "http" { name = "HTTP" }

resource "ztc_traffic_forwarding_rule" "allow_ingress_http" {
  name           = "${var.name_prefix}-allow-ingress-http"
  description    = "Allow inspected inbound HTTP locally to this lab's ALB subnets"
  forward_method = "LOCAL_SWITCH"
  type           = "EC_RDR"
  state          = "ENABLED"
  order          = var.rule_order
  rank           = var.rule_rank
  src_ips        = local.ztc_source_ips
  dest_addresses = local.destination_cidrs
  locations { id = [data.ztc_location_management.existing.id] }
  nw_services { id = [data.ztc_network_services.http.id] }
}
resource "ztc_traffic_forwarding_rule" "drop_other_ingress" {
  name           = "${var.name_prefix}-drop-other-ingress"
  description    = "Drop other inbound traffic to this lab's ALB subnets"
  forward_method = "DROP"
  type           = "EC_RDR"
  state          = "ENABLED"
  order          = var.rule_order + 1
  rank           = var.rule_rank
  # Omit src_ips for any source; the API rejects the explicit /0 range.
  dest_addresses = local.destination_cidrs
  locations { id = [data.ztc_location_management.existing.id] }
  # No nw_services restriction: match other services as well as other clients.
  depends_on = [ztc_traffic_forwarding_rule.allow_ingress_http]
}
# Capture only configured values and stable IDs. Provider readback can normalize
# optional fields (null -> false/empty), so never use the full resource as input.
resource "terraform_data" "policy_revision" {
  count = var.enable_policy_activation ? 1 : 0
  input = {
    allow_id            = ztc_traffic_forwarding_rule.allow_ingress_http.rule_id
    drop_id             = ztc_traffic_forwarding_rule.drop_other_ingress.rule_id
    location_id         = data.ztc_location_management.existing.id
    service_id          = data.ztc_network_services.http.id
    sources             = local.ztc_source_ips
    destinations        = local.destination_cidrs
    order               = var.rule_order
    rank                = var.rule_rank
    activation_revision = var.activation_revision
  }
}
resource "ztc_activation_status" "this" {
  count      = var.enable_policy_activation ? 1 : 0
  depends_on = [ztc_traffic_forwarding_rule.allow_ingress_http, ztc_traffic_forwarding_rule.drop_other_ingress, terraform_data.policy_revision]
  lifecycle {
    replace_triggered_by = [terraform_data.policy_revision[0]]
    ignore_changes       = [org_edit_status, org_last_activate_status, admin_activate_status]
  }
}

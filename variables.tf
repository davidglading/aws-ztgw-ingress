variable "aws_region" {
  description = "AWS region containing the existing ZTGW GWLB service."
  type        = string
  default     = "us-west-1"
}
variable "name_prefix" {
  description = "Unique lab prefix, 1–20 lowercase letters, digits, and hyphens; start with a letter and end with a letter/digit."
  type        = string
  default     = "ztgw-ingress"
  validation {
    condition     = length(var.name_prefix) <= 20 && can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be 1–20 lowercase letters/digits/hyphens, starting with a letter and ending with a letter or digit."
  }
}
variable "vpc_cidr" {
  description = "IPv4 VPC network CIDR, /16 through /24. The default follows the diagram's Web VPC."
  type        = string
  default     = "10.10.11.0/24"
  validation {
    condition = try(
      cidrnetmask(var.vpc_cidr) != "" && tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 24 && cidrsubnet(var.vpc_cidr, 0, 0) == var.vpc_cidr, false
    )
    error_message = "Supply a canonical IPv4 network CIDR between /16 and /24."
  }
}
variable "ztgw_endpoint_service_name" {
  description = "Existing Zscaler GWLB endpoint service name in aws_region. Authorize this AWS account on that service first."
  type        = string
  validation {
    condition     = can(regex("^com\\.amazonaws(\\.cn)?\\.vpce\\.[a-z0-9-]+\\.vpce-svc-[0-9a-f]+$", var.ztgw_endpoint_service_name))
    error_message = "Supply the real GWLB service name, e.g. com.amazonaws.vpce.us-west-1.vpce-svc-<id>."
  }
}
variable "ztgw_location_name" {
  description = "Existing ZTC location associated with the selected ZTGW. Used to scope the Zscaler forwarding rules in this apply."
  type        = string
  validation {
    condition     = length(trimspace(var.ztgw_location_name)) > 0
    error_message = "ztgw_location_name must name the existing gateway's ZTC location."
  }
}
variable "availability_zones" {
  description = "Optional two standard AZ names supported by the GWLB service. Empty discovers the first two supported/available AZs."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.availability_zones) == 0 || (length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2)
    error_message = "availability_zones must be empty or contain exactly two distinct AZ names."
  }
}
variable "allowed_client_cidrs" {
  description = "IPv4 clients allowed to reach HTTP/80. Use your public client /32 to restrict the lab; 0.0.0.0/0 permits all internet clients."
  type        = set(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.allowed_client_cidrs) > 0 && alltrue([for cidr in var.allowed_client_cidrs : can(cidrnetmask(cidr))])
    error_message = "Provide at least one valid IPv4 client CIDR."
  }
}
variable "web_instance_count" {
  description = "One private web instance for the basic lab, or two for a backend in each AZ."
  type        = number
  default     = 1
  validation {
    condition     = contains([1, 2], var.web_instance_count)
    error_message = "web_instance_count must be 1 or 2."
  }
}
variable "instance_type" {
  description = "x86_64 EC2 instance type available in both selected AZs."
  type        = string
  default     = "t3.micro"
}
variable "enable_ssm" {
  description = "Create an SSM instance profile and ssm/ssmmessages interface endpoints for private management."
  type        = bool
  default     = true
}

variable "rule_order" {
  description = "Position of the HTTP allow rule; the lab's DROP rule follows immediately after it. Review existing tenant rules first."
  type        = number
  default     = 1
  validation {
    condition     = var.rule_order >= 1 && floor(var.rule_order) == var.rule_order
    error_message = "rule_order must be a positive integer."
  }
}
variable "rule_rank" {
  type    = number
  default = 7
  validation {
    condition     = var.rule_rank >= 0 && var.rule_rank <= 7 && floor(var.rule_rank) == var.rule_rank
    error_message = "rule_rank must be an integer between 0 and 7."
  }
}
variable "enable_policy_activation" {
  description = "Activate after creating/updating rules. Tenant-wide: review all pending edits before enabling. False leaves draft changes for manual activation."
  type        = bool
  default     = true
}
variable "activation_revision" {
  description = "Change this string to request activation again when rules themselves have not changed."
  type        = string
  default     = "1"
}
variable "ztc_client_id" {
  type      = string
  default   = null
  sensitive = true
}
variable "ztc_client_secret" {
  type      = string
  default   = null
  sensitive = true
}
variable "ztc_private_key" {
  type      = string
  default   = null
  sensitive = true
}
variable "ztc_vanity_domain" {
  type    = string
  default = null
}
variable "zscaler_cloud" {
  description = "Optional non-production OneAPI environment, e.g. beta. Leave null for production."
  type        = string
  default     = null
}

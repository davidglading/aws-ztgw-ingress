data "aws_ami" "web" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Internet HTTP to the inspected ALB"
  vpc_id      = aws_vpc.web.id
  ingress {
    description = "HTTP from permitted internet clients"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = sort(tolist(var.allowed_client_cidrs))
  }
  # CIDR-scoped egress avoids a circular dependency with the web SG.
  egress {
    description = "HTTP and health checks to private web subnets"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [for slot in values(local.az_slots) : slot.web_cidr]
  }
}
resource "aws_security_group" "web" {
  name_prefix = "${var.name_prefix}-web-"
  description = "Private website: HTTP only from the ALB"
  vpc_id      = aws_vpc.web.id
  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  # Optional SSM endpoints are local to this VPC; no internet egress is needed.
  egress {
    description = "HTTPS to VPC management endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}
resource "aws_lb" "web" {
  name                       = "${var.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  subnets                    = [for key in sort(keys(local.az_slots)) : aws_subnet.alb[key].id]
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  depends_on = [
    aws_route_table_association.igw_ingress, aws_route.alb_return_inspection,
    aws_route.inspection_internet, aws_route_table_association.alb,
    aws_route_table_association.inspection
  ]
}
resource "aws_lb_target_group" "web" {
  name_prefix = "web-"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.web.id
  health_check {
    enabled = true
    path    = "/"
    port    = "traffic-port"
    matcher = "200"
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
resource "aws_instance" "web" {
  for_each                    = local.web_slots
  ami                         = data.aws_ami.web.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.web[each.key].id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = var.enable_ssm ? aws_iam_instance_profile.ssm[0].name : null
  user_data                   = templatefile("${path.module}/templates/web-user-data.sh.tftpl", { name_prefix = var.name_prefix, az = each.value.az })
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  root_block_device {
    encrypted = true
  }
  tags = { Name = "${var.name_prefix}-web-${each.key}" }
}
resource "aws_lb_target_group_attachment" "web" {
  for_each         = local.web_slots
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[each.key].id
  port             = 80
}

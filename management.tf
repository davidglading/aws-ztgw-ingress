data "aws_partition" "current" {}
resource "aws_iam_role" "ssm" {
  count       = var.enable_ssm ? 1 : 0
  name_prefix = "${var.name_prefix}-ssm-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.enable_ssm ? 1 : 0
  role       = aws_iam_role.ssm[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "ssm" {
  count       = var.enable_ssm ? 1 : 0
  name_prefix = "${var.name_prefix}-ssm-"
  role        = aws_iam_role.ssm[0].name
}
resource "aws_security_group" "ssm" {
  count       = var.enable_ssm ? 1 : 0
  name_prefix = "${var.name_prefix}-ssm-"
  description = "SSM interface endpoints: HTTPS from web instances"
  vpc_id      = aws_vpc.web.id
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }
}
resource "aws_vpc_endpoint" "ssm" {
  for_each            = var.enable_ssm ? toset(["ssm", "ssmmessages"]) : toset([])
  vpc_id              = aws_vpc.web.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for key in sort(keys(local.az_slots)) : aws_subnet.web[key].id]
  security_group_ids  = [aws_security_group.ssm[0].id]
  tags                = { Name = "${var.name_prefix}-${each.key}" }
}

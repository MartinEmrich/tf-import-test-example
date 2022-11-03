variable "platform_name" {
  type = string
}
variable "platform_cidr" {
  default = "10.40.0.0/16"
  type    = string
}

variable "availability_zones" {
  type    = list(string)
  default = ["a", "b", "c"]
}

data "aws_region" "current" {}

locals {
  public_cidr        = cidrsubnet(var.platform_cidr, 2, 3)
  availability_zones = { for az in var.availability_zones : az => az }
  subnet_parts = {
    "a" : "01::/64"
    "b" : "02::/64"
    "c" : "03::/64"
    "d" : "04::/64"
    "e" : "05::/64"
  }
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.platform_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    "Name" : var.platform_name
    # Tag for EKS. Would be removed otherwise by TF if only added by eksctl....
    "kubernetes.io/cluster/${var.platform_name}" : "shared"
  }
  assign_generated_ipv6_cidr_block = true
}

resource "aws_subnet" "public_subnet" {
  for_each                = local.availability_zones
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.name}${each.key}"
  cidr_block              = cidrsubnet(local.public_cidr, 2, index(keys(local.availability_zones), each.key))
  ipv6_cidr_block         = join("", [trimsuffix(aws_vpc.vpc.ipv6_cidr_block, "00::/56"), local.subnet_parts[each.key]])
  map_public_ip_on_launch = true
  tags = {
    "Name" : "${var.platform_name}-public-${each.key}",
    "kubernetes.io/role/elb" : "1"
    # Tag for EKS. Would be removed otherwise by TF if only added by eksctl....
    "kubernetes.io/cluster/${var.platform_name}" : "shared"
  }
}

resource "aws_subnet" "private_subnet" {
  for_each                = local.availability_zones
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = "${data.aws_region.current.name}${each.key}"
  cidr_block              = cidrsubnet(var.platform_cidr, 2, index(keys(local.availability_zones), each.key))
  map_public_ip_on_launch = false
  tags = {
    "Name" : "${var.platform_name}-private-${each.key}",
    "kubernetes.io/role/internal-elb" : "1",
    # Tag to make karpenter (https://karpenter.sh) use the network
    "karpenter.sh/discovery" = "${var.platform_name}"
  }
}

resource "aws_route_table" "route_table_public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" : "${var.platform_name}-route-table-public"
  }

}
resource "aws_route_table" "route_tables_private" {
  for_each = local.availability_zones
  vpc_id   = aws_vpc.vpc.id
  tags = {
    "Name" : "${var.platform_name}-route-table-private-${each.key}"
  }
}

resource "aws_route_table_association" "route_table_association_public" {
  for_each       = local.availability_zones
  subnet_id      = aws_subnet.public_subnet[each.key].id
  route_table_id = aws_route_table.route_table_public.id
}

resource "aws_route_table_association" "route_table_association_private" {
  for_each       = local.availability_zones
  subnet_id      = aws_subnet.private_subnet[each.key].id
  route_table_id = aws_route_table.route_tables_private[each.key].id
}

resource "aws_internet_gateway" "internet_gateway" {
  tags = {
    "Name" : "${var.platform_name}-internet-gateway"
  }
  # attachment
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route" "route_public_ipv4" {
  route_table_id         = aws_route_table.route_table_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_route" "route_public_ipv6" {
  route_table_id              = aws_route_table.route_table_public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.internet_gateway.id
}

resource "aws_eip" "nat_gateway_ip" {
  for_each = local.availability_zones
  vpc      = true
  tags = {
    "Name" : "${var.platform_name} NAT Gateway Elastic IP ${each.key}"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  for_each = local.availability_zones
  depends_on = [
    aws_eip.nat_gateway_ip
  ]
  subnet_id     = aws_subnet.public_subnet[each.key].id
  allocation_id = aws_eip.nat_gateway_ip[each.key].id
  tags = {
    "Name" : "${var.platform_name} NAT Gateway ${each.key}"
  }
}
resource "aws_route" "nat_gateway_route" {
  for_each               = local.availability_zones
  route_table_id         = aws_route_table.route_tables_private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gateway[each.key].id
}

resource "aws_security_group" "internal" {
  name        = "${var.platform_name}-internal"
  description = "Intern"
  vpc_id      = aws_vpc.vpc.id
  tags = {
    "karpenter.sh/discovery" = "${var.platform_name}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "internal_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.internal.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_vpc_endpoint" "s3_endpoint" {
  route_table_ids = concat(
    [
      aws_route_table.route_table_public.id
    ],
    [for key in keys(local.availability_zones) : aws_route_table.route_tables_private[key].id]
  )
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_id       = aws_vpc.vpc.id
}

output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "security_group_internal_id" {
  value = aws_security_group.internal.id
}

output "private_subnets" {
  value = aws_subnet.private_subnet
}
output "public_subnets" {
  value = aws_subnet.public_subnet
}

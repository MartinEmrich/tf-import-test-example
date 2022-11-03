terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.2.0"
    }
  }
}

variable "platform_name" {
  type = string
}

variable "platform_dns_domain" {
  type = string
}

variable "platform_cidr" {
  default = "10.40.0.0/16"
  type    = string
}

variable "management_key_pair" {
  type        = string
  description = "AWS EC2 Key Pair name to be used during creation of management host."
}

variable "availability_zones" {
  type    = list(string)
  default = ["a", "b", "c"]
}

data "aws_region" "current" {}

module "vpc" {
  source             = "./vpc"
  platform_cidr      = var.platform_cidr
  platform_name      = var.platform_name
  availability_zones = var.availability_zones
}

module "management_host" {
  source                     = "./managementhost"
  management_host_subnet     = module.vpc.public_subnets["a"]
  vpc_id                     = module.vpc.vpc_id
  platform_name              = var.platform_name
  management_key_pair        = var.management_key_pair
  security_group_internal_id = module.vpc.security_group_internal_id
  route_53_hosted_zone_id    = aws_route53_zone.platformdomain.zone_id
  platform_dns_domain        = var.platform_dns_domain
  private_subnets            = module.vpc.private_subnets
}

resource "aws_security_group_rule" "internal_hosts_ssh" {
  type                     = "ingress"
  description              = "SSH from management hosts"
  protocol                 = "tcp"
  from_port                = 22
  to_port                  = 22
  security_group_id        = module.vpc.security_group_internal_id
  source_security_group_id = module.management_host.security_group_id
}

resource "aws_security_group_rule" "internal_hosts_private" {
  type              = "ingress"
  description       = "all internal traffic"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  security_group_id = module.vpc.security_group_internal_id
  cidr_blocks       = [for subnet in module.vpc.private_subnets : subnet.cidr_block]
}

resource "aws_route53_zone" "platformdomain" {
  name          = var.platform_dns_domain
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

output "management_host_private_ip" {
  value = module.management_host.private_ip
}

output "management_host_public_ip" {
  value = module.management_host.public_ip
}

output "vpc_private_subnets" {
  value = { for az in keys(module.vpc.private_subnets) : az => module.vpc.private_subnets[az].id }
}
output "vpc_public_subnets" {
  value = { for az in keys(module.vpc.public_subnets) : az => module.vpc.public_subnets[az].id }
}

output "route_53_hosted_zone_id" {
  value = aws_route53_zone.platformdomain.zone_id
}

output "security_group_internal_id" {
  value = module.vpc.security_group_internal_id
}

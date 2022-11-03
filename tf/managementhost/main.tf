variable "management_host_subnet" {
  type        = object({ id = string, cidr_block = string })
  description = "Subnet for the management host"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "platform_name" {
  type = string
}
variable "management_key_pair" {
  type = string
}

variable "security_group_internal_id" {
  type = string
}

variable "platform_dns_domain" {
  type = string
}

variable "route_53_hosted_zone_id" {
  type = string
}

variable "private_subnets" {
  type = map(any)
}
data "aws_subnet" "private_subnets" {
  for_each = var.private_subnets
  id       = var.private_subnets[each.key].id
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Amazon Linux 2
data "aws_ami" "aws_ami" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-2*x86_64-gp2"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_eip" "management_host" {
  instance = aws_instance.management_host.id
  vpc      = true
}

resource "aws_security_group" "management_host" {
  name        = "ManagementHost"
  description = "SSH access to management host"
  vpc_id      = var.vpc_id
  ingress = [
    {
      description      = "SSH"
      protocol         = "tcp"
      from_port        = 22
      to_port          = 22
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = null
      security_groups  = null
      self             = null
    }
  ]
  egress = [
    {
      description      = "all"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = null
      security_groups  = null
      self             = null
    }
  ]
}

resource "aws_instance" "management_host" {
  key_name                = var.management_key_pair
  disable_api_termination = false
  ami                     = data.aws_ami.aws_ami.image_id
  instance_type           = "t3.small"
  monitoring              = false
  vpc_security_group_ids = [
    aws_security_group.management_host.id,
    var.security_group_internal_id
  ]
  subnet_id     = var.management_host_subnet.id
  private_ip    = cidrhost(var.management_host_subnet.cidr_block, 4)
  ebs_optimized = true
  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 20
  }
  iam_instance_profile = aws_iam_instance_profile.management_host.id
  user_data = trimspace(<<-EOT
    #!/bin/bash -ex
    dd if=/dev/zero of=/opt/swapfile bs=1M count=1024
    mkswap /opt/swapfile
    chmod og-rwx /opt/swapfile
    echo '/opt/swapfile        swap                  swap defaults 1 1' >> /etc/fstab
    swapon -a
    yum update -y
    yum clean expire-cache
    yum install -y awscli jq lvm2
    amazon-linux-extras install epel -y
  EOT
  )
  tags = {
    "Name" : "management-host ${var.platform_name}"
  }
  lifecycle {
    ignore_changes = [
      ami
    ]
  }
}

resource "null_resource" "management_host_wait_for_installation" {
  depends_on = [
    aws_instance.management_host,
    aws_eip.management_host
  ]

  triggers = {
    instance_id        = aws_instance.management_host.id
    eip_allocation_id  = aws_eip.management_host.allocation_id
    eip_association_id = aws_eip.management_host.association_id
  }
  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait"
    ]
    connection {
      host        = aws_eip.management_host.public_ip
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.cwd}/${var.management_key_pair}.pem")
    }
  }
}

resource "aws_route53_record" "management_host" {
  depends_on = [
    aws_eip.management_host
  ]
  name    = "mgmt.${var.platform_dns_domain}"
  type    = "A"
  ttl     = 300
  zone_id = var.route_53_hosted_zone_id
  records = [aws_eip.management_host.public_ip]
}

output "security_group_id" {
  value = aws_security_group.management_host.id
}

output "public_ip" {
  value = aws_eip.management_host.public_ip
}

output "private_ip" {
  value = aws_instance.management_host.private_ip
}

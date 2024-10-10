terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.69.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "prefix" {
  type    = string
  default = "graph-run-task"
}

provider "aws" {
  region = var.region
}

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.prefix}-key"
  public_key = tls_private_key.demo.public_key_openssh

  tags = {
    Name = "${var.prefix}-key-pair"
  }
}

resource "aws_vpc" "demo" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.prefix}-vpc"
  }
}

resource "aws_subnet" "demo" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.prefix}-subnet"
  }
}

resource "aws_security_group" "demo" {
  name        = "${var.prefix}-sg"
  description = "Allow 22 and 80 for demo inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.demo.id

  tags = {
    Name = "${var.prefix}-security-group"
  }
}

resource "aws_security_group_rule" "demo_app" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.demo.id
}

resource "aws_security_group_rule" "demo_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.demo.id
}

resource "aws_security_group_rule" "demo_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.demo.id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "demo" {
  ami                         = data.aws_ami.ubuntu.id
  availability_zone           = "${var.region}a"
  instance_type               = "t2.small"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated_key.key_name
  vpc_security_group_ids      = [aws_security_group.demo.id]
  subnet_id                   = aws_subnet.demo.id
  user_data                   = data.template_file.cloud-init.rendered

  tags = {
    Name = "${var.prefix}-instance"
  }
}

data "template_file" "cloud-init" {
  template = file("cloud-init.tpl")
}

resource "local_file" "private_key" {
  content         = tls_private_key.demo.private_key_pem
  filename        = "${path.module}/private_key.pem"
  file_permission = "0600"
}

resource "null_resource" "get_logs" {
  depends_on = [aws_instance.demo]

  provisioner "local-exec" {
    command = <<-EOT
      sleep 180
      ssh -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} ubuntu@${aws_instance.demo.public_ip} 'sudo cat /var/log/cloud-init-output.log' > cloud-init-output.log
      ssh -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} ubuntu@${aws_instance.demo.public_ip} 'sudo cat /var/log/cloud-init.log' > cloud-init.log
    EOT
  }
}

data "local_file" "cloud_init_output_log" {
  depends_on = [null_resource.get_logs]
  filename   = "${path.module}/cloud-init-output.log"
}

data "local_file" "cloud_init_log" {
  depends_on = [null_resource.get_logs]
  filename   = "${path.module}/cloud-init.log"
}

output "aws_instance_login_information" {
  value = <<INSTANCEIP
  http://${aws_instance.demo.public_ip}
INSTANCEIP
}

output "aws_key_pair_info" {
  value = nonsensitive(tls_private_key.demo.private_key_openssh)
}

output "cloud_init_output_log" {
  value = data.local_file.cloud_init_output_log.content
}

output "cloud_init_log" {
  value = data.local_file.cloud_init_log.content
}
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
}

resource "aws_vpc" "demo" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "demo" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"
}

resource "aws_security_group" "demo" {
  name        = "${var.prefix}-sg"
  description = "Allow 22 and 80 for demo inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.demo.id
}

/*
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

# New rule for EC2 Instance Connect
resource "aws_security_group_rule" "instance_connect" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["3.16.146.0/29", "3.22.11.0/29", "18.206.107.24/29", "3.80.101.78/32", "3.91.186.242/32", "3.132.215.46/32"]
  security_group_id = aws_security_group.demo.id
  description       = "Allow EC2 Instance Connect"
}
*/

resource "aws_security_group_rule" "everything" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
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

# New IAM role for EC2 Instance Connect
resource "aws_iam_role" "instance_connect_role" {
  name = "${var.prefix}-instance-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policy to allow EC2 Instance Connect
resource "aws_iam_role_policy_attachment" "instance_connect_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.instance_connect_role.name
}

# Create instance profile
resource "aws_iam_instance_profile" "instance_connect_profile" {
  name = "${var.prefix}-instance-connect-profile"
  role = aws_iam_role.instance_connect_role.name
}

resource "aws_instance" "demo" {
  ami                         = data.aws_ami.ubuntu.id
  availability_zone           = "${var.region}a"
  instance_type               = "t2.small"
  associate_public_ip_address = "true"
  key_name                    = aws_key_pair.generated_key.key_name
  vpc_security_group_ids      = [aws_security_group.demo.id]
  subnet_id                   = aws_subnet.demo.id
  user_data                   = data.template_file.cloud-init.rendered
  iam_instance_profile        = aws_iam_instance_profile.instance_connect_profile.name

  tags = {
    Name = "${var.prefix}-instance"
  }
}

data "template_file" "cloud-init" {
  template = file("cloud-init.tpl")
}

output "aws_instance_login_information" {
  value = <<INSTANCEIP
  http://${aws_instance.demo.public_ip}
INSTANCEIP
}

output "aws_key_pair_info" {
  value = nonsensitive(tls_private_key.demo.private_key_openssh)
}
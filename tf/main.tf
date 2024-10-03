terraform {
  required_providers {
    tfe = {
      source = "hashicorp/tfe"
      version = "0.59.0"
    }
    aws = {
      source = "hashicorp/aws"
      version = "5.69.0"
    }
  }
}

provider "tfe" {
  # Configuration options
}

provider "aws" {
  region = "us-west-2"
}

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "${random_pet.server.id}-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "random_pet" "server" {}

resource "aws_vpc" "demo" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "demo" {
  vpc_id     = aws_vpc.demo.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_security_group" "demo" {
  name        = "${random_pet.server.id}-sg"
  description = "Allow 22 and 80 for demo inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.demo.id
}

resource "aws_security_group_rule" "demo_app" {
  type        = "ingress"
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  #cidr_blocks       = [aws_vpc.demo.cidr_block]
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
  ami = data.aws_ami.ubuntu.id

  instance_type               = "t2.small"
  associate_public_ip_address = "true"
  key_name                    = aws_key_pair.generated_key.key_name
  vpc_security_group_ids      = [aws_security_group.demo.id]
  subnet_id                   = aws_subnet.demo.id
  user_data                   = data.template_file.cloud-init.rendered
}

data "template_file" "cloud-init" {
  template = file("cloud-init.tpl")

}

output "aws_instance_login_information" {
  value = <<INSTANCEIP
  http://@${aws_instance.demo.public_ip}
INSTANCEIP
}

variable "ddr_tfc_organization" {
  type        = string
  description = "The name of the Terraform Cloud organization"
}


resource "tfe_organization_run_task" "demo" {
  organization = var.ddr_tfc_organization
  url         = "http://${aws_instance.demo.public_ip}"
  name        = "TerraformGraph"
  enabled     = true
  description = "HCP Terraform Run Task for Graph"
}
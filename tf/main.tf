provider "aws" {
  region = "us-west-2"
}

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "demo-key"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "random_pet" "server" {}

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

  user_data = data.template_file.cloud-init.rendered
}

data "template_file" "cloud-init" {
  template = file("cloud-init.tpl")

}
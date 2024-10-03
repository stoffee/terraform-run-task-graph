terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.69.0"
    }
    tfe = {
      source = "hashicorp/tfe"
      version = "0.59.0"
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
  vars = {
    hmac_key = random_id.hmac_key.hex
  }
}

output "aws_instance_login_information" {
  value = <<INSTANCEIP
  http://${aws_instance.demo.public_ip}
INSTANCEIP
}

# In your main.tf or a separate tf file

# Generate a random HMAC key
resource "random_id" "hmac_key" {
  byte_length = 64  # 512 bits
}

# Output the HMAC key
output "hmac_key" {
  value     = random_id.hmac_key.hex
  sensitive = true
}

# Create the run task with the generated HMAC key
# Variable declaration for TFC organization
variable "tfc_organization" {
  description = "The name of the Terraform Cloud organization"
  type        = string
}

resource "tfe_organization_run_task" "demo" {
  organization = var.tfc_organization
  url          = "http://${aws_instance.demo.public_ip}"
  name         = "TerraformGraph"
  enabled      = true
  hmac_key     = random_id.hmac_key.hex
}

# Variable declaration for TFC workspace
variable "tfc_workspace" {
  description = "The name of the Terraform Cloud workspace"
  type        = string
}

data "tfe_workspace" "demo" {
  name         = var.tfc_workspace
  organization = var.tfc_organization
}

resource "tfe_workspace_run_task" "demo" {
  workspace_id      = data.tfe_workspace.demo.id
  task_id           = resource.tfe_organization_run_task.demo.id
  enforcement_level = "mandatory"
  stages = ["post_plan"]
}
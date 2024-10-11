terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.69.0"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.42.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "prefix" {
  type    = string
  default = "secure-graph-run-task"
}

variable "tfe_organization" {
  type        = string
  description = "The name of the Terraform Cloud organization"
}

variable "oauth_token_id" {
  type        = string
  description = "The OAuth token ID for connecting to VCS"
}

variable "hmac_key" {
  type        = string
  description = "HMAC key for the run task"
  sensitive   = true
}

provider "aws" {
  region = var.region
}

provider "tfe" {
  organization = var.tfe_organization
}

resource "tls_private_key" "app" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "${var.prefix}-key"
  public_key = tls_private_key.app.public_key_openssh
}

resource "aws_vpc" "app" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "app" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app.id
}

resource "aws_security_group" "app" {
  name        = "${var.prefix}-sg"
  description = "Allow 22 and 80 for app inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.app.id
}

resource "aws_security_group_rule" "app_app" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
}

resource "aws_security_group_rule" "app_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
}

resource "aws_security_group_rule" "app_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
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

resource "aws_iam_role_policy_attachment" "instance_connect_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.instance_connect_role.name
}

resource "aws_iam_instance_profile" "instance_connect_profile" {
  name = "${var.prefix}-instance-connect-profile"
  role = aws_iam_role.instance_connect_role.name
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  availability_zone           = "${var.region}a"
  instance_type               = "t2.small"
  associate_public_ip_address = "true"
  key_name                    = aws_key_pair.generated_key.key_name
  vpc_security_group_ids      = [aws_security_group.app.id]
  subnet_id                   = aws_subnet.app.id
  user_data                   = data.template_file.cloud-init.rendered
  iam_instance_profile        = aws_iam_instance_profile.instance_connect_profile.name
  tags = {
    Name = "${var.prefix}-instance"
  }
}

data "template_file" "cloud-init" {
  template = file("cloud-init.tpl")
  vars = {
    hmac_key = var.hmac_key
  }
}

resource "time_sleep" "wait_for_server" {
  depends_on      = [aws_instance.app]
  create_duration = "94s"
}

resource "tfe_organization_run_task" "app_task" {
  depends_on   = [time_sleep.wait_for_server]
  organization = var.tfe_organization
  url          = "http://${aws_instance.app.public_ip}"
  name         = var.prefix
  enabled      = true
  hmac_key     = var.hmac_key
  description  = "Run task for ${var.prefix} application"
}

# New workspace
resource "tfe_workspace" "demo" {
  name         = "secure-demo-server-workspace"
  organization = var.tfe_organization

  vcs_repo {
    identifier     = "stoffee/terraform-run-task-graph"
    branch         = "main"
    oauth_token_id = var.oauth_token_id
  }

  working_directory = "tf/demo_server"
}

# Attach run task to the new workspace
resource "tfe_workspace_run_task" "demo" {
  workspace_id      = tfe_workspace.demo.id
  task_id           = tfe_organization_run_task.app_task.id
  enforcement_level = "advisory"
}

output "aws_instance_login_information" {
  value = <<INSTANCEIP
  http://${aws_instance.app.public_ip}
INSTANCEIP
}

output "tfe_run_task_id" {
  value = tfe_organization_run_task.app_task.id
}

output "demo_workspace_id" {
  value = tfe_workspace.demo.id
}
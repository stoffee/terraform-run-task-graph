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
  default = "demo-graph-run-task"
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

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id
}

resource "aws_route_table" "demo" {
  vpc_id = aws_vpc.demo.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }
}

resource "aws_route_table_association" "demo" {
  subnet_id      = aws_subnet.demo.id
  route_table_id = aws_route_table.demo.id
}

resource "aws_security_group" "demo" {
  name        = "${var.prefix}-sg"
  description = "Allow 22 and 80 for demo inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.demo.id
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

resource "aws_security_group_rule" "demo_outbound" {
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

resource "aws_instance" "demo" {
  ami                         = data.aws_ami.ubuntu.id
  availability_zone           = "${var.region}a"
  instance_type               = "t2.small"
  associate_public_ip_address = "true"
  key_name                    = aws_key_pair.generated_key.key_name
  vpc_security_group_ids      = [aws_security_group.demo.id]
  subnet_id                   = aws_subnet.demo.id
  iam_instance_profile        = aws_iam_instance_profile.instance_connect_profile.name
  tags = {
    Name = "${var.prefix}-instance"
  }
}

# New resources start here

# 1. Elastic IP
resource "aws_eip" "demo" {
  instance = aws_instance.demo.id
  domain   = "vpc"
}

# 2. S3 bucket
resource "aws_s3_bucket" "demo" {
  bucket = "${var.prefix}-bucket"
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. CloudWatch Log Group
resource "aws_cloudwatch_log_group" "demo" {
  name              = "/aws/ec2/${aws_instance.demo.id}"
  retention_in_days = 30
}

# 6. Network ACL
resource "aws_network_acl" "demo" {
  vpc_id = aws_vpc.demo.id

  egress {
    protocol   = "-1"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  tags = {
    Name = "${var.prefix}-nacl"
  }
}

resource "aws_network_acl_association" "demo" {
  network_acl_id = aws_network_acl.demo.id
  subnet_id      = aws_subnet.demo.id
}

output "aws_instance_login_information" {
  value = <<INSTANCEIP
  http://${aws_eip.demo.public_ip}
INSTANCEIP
}

output "aws_key_pair_info" {
  value = nonsensitive(tls_private_key.demo.private_key_openssh)
}

output "s3_bucket_name" {
  value = aws_s3_bucket.demo.id
}

output "cloudwatch_log_group_name" {
  value = aws_cloudwatch_log_group.demo.name
}
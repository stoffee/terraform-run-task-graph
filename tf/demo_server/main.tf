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

# 4. RDS Instance
resource "aws_db_subnet_group" "demo" {
  name       = "${var.prefix}-db-subnet-group"
  subnet_ids = [aws_subnet.demo.id, aws_subnet.demo_secondary.id]
}

resource "aws_db_instance" "demo" {
  identifier           = "${var.prefix}-db-instance"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  db_name              = "demodb"
  username             = "admin"
  password             = "password123"  # Use aws_secretsmanager_secret in production
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.demo.name
  vpc_security_group_ids = [aws_security_group.demo_db.id]
}

resource "aws_security_group" "demo_db" {
  name        = "${var.prefix}-db-sg"
  description = "Allow inbound traffic to RDS"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.demo.id]
  }
}

# 5. ELB
resource "aws_lb" "demo" {
  name               = "${var.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_alb.id]
  subnets            = [aws_subnet.demo.id, aws_subnet.demo_secondary.id]
}

resource "aws_lb_target_group" "demo" {
  name     = "${var.prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo.id
}

resource "aws_lb_target_group_attachment" "demo" {
  target_group_arn = aws_lb_target_group.demo.arn
  target_id        = aws_instance.demo.id
  port             = 80
}

resource "aws_lb_listener" "demo" {
  load_balancer_arn = aws_lb.demo.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }
}

resource "aws_security_group" "demo_alb" {
  name        = "${var.prefix}-alb-sg"
  description = "Allow inbound traffic to ALB"
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. SNS Topic
resource "aws_sns_topic" "demo" {
  name = "${var.prefix}-sns-topic"
}

resource "aws_sns_topic_subscription" "demo" {
  topic_arn = aws_sns_topic.demo.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"
}

# 7. Lambda Function
resource "aws_iam_role" "demo_lambda" {
  name = "${var.prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_lambda_function" "demo" {
  function_name = "${var.prefix}-lambda"
  role          = aws_iam_role.demo_lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs14.x"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.demo.arn
    }
  }

  # Inline Lambda function code
  filename = "lambda_function.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [aws_iam_role_policy_attachment.lambda_logs, aws_cloudwatch_log_group.lambda_log_group]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source {
    content  = <<EOF
exports.handler = async (event) => {
  console.log('Hello from Lambda!');
  return {
    statusCode: 200,
    body: JSON.stringify('Hello from Lambda!'),
  };
};
EOF
    filename = "index.js"
  }
}

# CloudWatch Logs for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.prefix}-lambda"
  retention_in_days = 14
}

# IAM policy for logging from Lambda
resource "aws_iam_policy" "lambda_logging" {
  name        = "${var.prefix}-lambda-logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Attach the logging policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.demo_lambda.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

# 8. DynamoDB Table
resource "aws_dynamodb_table" "demo" {
  name           = "${var.prefix}-dynamodb-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "Id"

  attribute {
    name = "Id"
    type = "S"
  }
}

# Additional subnet for RDS and ALB
resource "aws_subnet" "demo_secondary" {
  vpc_id            = aws_vpc.demo.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}b"
}

# Update EC2 instance to allow communication with new resources
resource "aws_security_group_rule" "demo_to_rds" {
  type                     = "egress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.demo_db.id
  security_group_id        = aws_security_group.demo.id
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

output "rds_endpoint" {
  value = aws_db_instance.demo.endpoint
}

output "alb_dns_name" {
  value = aws_lb.demo.dns_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.demo.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.demo.function_name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.demo.name
}
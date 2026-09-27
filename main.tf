terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "alert_email" {
  description = "Your email address for lab alerts."
  type        = string
  sensitive   = true
}

resource "aws_sns_topic" "alerts" {
  name = "linux-lab-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "instance_health" {
  alarm_name        = "linux-lab-status-check"
  alarm_description = "Notify when the lab EC2 instance fails status checks."

  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = aws_instance.web.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Settings: the AWS region and the single public IPv4 address allowed to view Nginx.
variable "aws_region" {
  description = "AWS region for this disposable lab."
  type        = string
  default     = "us-east-1"
}

variable "allowed_http_cidr" {
  description = "Your current public IPv4 address followed by /32."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_http_cidr)) && endswith(var.allowed_http_cidr, "/32")
    error_message = "Use one public IPv4 address followed by /32."
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "aws-linux-infrastructure-lab"
      ManagedBy = "Terraform"
    }
  }
}

# Network: one subnet with a route to the internet. No default VPC is required.
resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "linux-lab" }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.lab.id
  cidr_block = "10.42.1.0/24"

  tags = { Name = "linux-lab-public" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = { Name = "linux-lab" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = "linux-lab-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Firewall: allow your browser on port 80. Administration uses Session Manager.
resource "aws_security_group" "web" {
  name_prefix = "linux-lab-"
  description = "Nginx HTTP from your public IP"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "Nginx from your public IPv4 address"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  egress {
    description = "Package downloads and Systems Manager connectivity"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "linux-lab-web" }
}

# Server identity: let the SSM agent connect to AWS for browser-based shell access.
resource "aws_iam_role" "server" {
  name_prefix = "linux-lab-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "session_manager" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "server" {
  name_prefix = "linux-lab-"
  role        = aws_iam_role.server.name
}

# Workload: a standard Amazon Linux image and the packaged Nginx welcome page.
data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "web" {
  ami                         = nonsensitive(data.aws_ssm_parameter.amazon_linux.value)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.server.name
  user_data_replace_on_change = true

  # Boot commands need the internet route and instance permissions to exist first.
  depends_on = [
    aws_route_table_association.public,
    aws_iam_role_policy_attachment.session_manager,
  ]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  # Standard credits avoid T3 surplus CPU credit charges in this small exercise.
  credit_specification {
    cpu_credits = "standard"
  }

  user_data = <<-BASH
    #!/bin/bash
    set -euo pipefail
    systemctl enable --now amazon-ssm-agent
    dnf install -y nginx
    systemctl enable --now nginx
  BASH

  tags = { Name = "linux-lab-nginx" }
}

output "website_url" {
  description = "Open with HTTP from the public IPv4 address allowed in your settings."
  value       = "http://${aws_instance.web.public_ip}"
}

output "instance_id" {
  description = "Select this instance in the EC2 console to connect through Session Manager."
  value       = aws_instance.web.id
}

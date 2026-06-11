terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  profile = "account-a"
  region  = var.aws_region
}


# Create IAM Role for ECS Task
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-resource-cleanup-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Create custom policy
resource "aws_iam_role_policy" "cleanup_policy" {
  name = "resource-cleanup-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.TARGET_ACCOUNT_ID}:role/aws-nuke-role"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.SOURCE_ACCOUNT_ID}:log-group:/ecs/resource-cleanup:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      }
    ]
  })
}

# Create ECS Cluster
resource "aws_ecs_cluster" "cleanup_cluster" {
  name = "resource-cleanup-cluster"
}

# Create ECS Task Definition
resource "aws_ecs_task_definition" "cleanup_task" {
  family                   = "resource-cleanup"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name    = "cleanup-container"
      image   = local.nuke_image
      command = ["nuke", "-c", "/app/nuke-config.yml", "--assume-role-arn", "arn:aws:iam::${var.TARGET_ACCOUNT_ID}:role/aws-nuke-role", "--no-prompt", "--no-dry-run", "--no-alias-check"]

      environment = [
        {
          name  = "TARGET_ACCOUNT_ID"
          value = var.TARGET_ACCOUNT_ID
        }
      ]

      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/resource-cleanup"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "cleanup_logs" {
  name              = "/ecs/resource-cleanup"
  retention_in_days = 7
}

# Create Security Group for ECS Task that allows outbound internet access only
resource "aws_security_group" "ecs_task_sg" {
  name        = "ecs-cleanup-task-sg"
  description = "Security group for resource cleanup ECS task"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


############# SCHEDULED TRIGGER ############# 

# Create CloudWatch Event Rule for midnight schedule
resource "aws_cloudwatch_event_rule" "midnight_trigger" {
  name                = "trigger-cleanup-task-midnight"
  description         = "Triggers resource cleanup task at midnight"
  schedule_expression = "cron(0 0 * * ? *)" # Runs at midnight (UTC) every day
}


# Create IAM Role for CloudWatch Events
resource "aws_iam_role" "cloudwatch_role" {
  name = "cloudwatch-ecs-trigger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

# Create IAM Policy for CloudWatch Events to run ECS Task
resource "aws_iam_role_policy" "cloudwatch_policy" {
  name = "cloudwatch-ecs-trigger-policy"
  role = aws_iam_role.cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = [
          aws_ecs_task_definition.cleanup_task.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.ecs_task_role.arn
        ]
      }
    ]
  })
}

# Create CloudWatch Event Target
resource "aws_cloudwatch_event_target" "ecs_scheduled_task" {
  rule      = aws_cloudwatch_event_rule.midnight_trigger.name
  target_id = "RunCleanupTask"
  arn       = aws_ecs_cluster.cleanup_cluster.arn
  role_arn  = aws_iam_role.cloudwatch_role.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.cleanup_task.arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets          = data.aws_subnets.default.ids
      security_groups  = [aws_security_group.ecs_task_sg.id]
      assign_public_ip = true
    }
  }
}


############### VARIABLES #############

locals {
  nuke_image = format("%s.dkr.ecr.%s.amazonaws.com/aws-nuke", var.SOURCE_ACCOUNT_ID, var.aws_region)
}


############### VARIABLES #############

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "eu-west-1"
}

variable "SOURCE_ACCOUNT_ID" {
  description = "The AWS Account ID where the ECS task will run (Account A)"
  type        = string
}

variable "TARGET_ACCOUNT_ID" {
  description = "The AWS Account ID to target for cleanup (Account B)"
  type        = string
}

############### DATA #############

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

############ OUTPUTS #############

output "security_group_id" {
  value = aws_security_group.ecs_task_sg.id
}
output "first_subnet_id" {
  value = data.aws_subnets.default.ids[0]
}
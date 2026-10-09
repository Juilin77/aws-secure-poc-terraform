############################################
# VPC Flow Logs
#
# Scope:
# - Entire Peter POC VPC
#
# Destination:
# - CloudWatch Logs
#
# Capture:
# - ACCEPT + REJECT
# - 60-second aggregation
############################################


############################################
# Current AWS Account
############################################

data "aws_caller_identity" "current" {}


############################################
# CloudWatch Log Group
############################################

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/peter-poc/flow-logs"
  retention_in_days = 90

  tags = {
    Name  = "peter-poc-vpc-flow-logs"
    email = var.owner_email
  }
}


############################################
# IAM Role for VPC Flow Logs
############################################

resource "aws_iam_role" "vpc_flow_logs" {
  name = "peter-poc-vpc-flow-logs-role"

  #
  # Required by current account governance
  #
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/PermissionsBoundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowVPCFlowLogsAssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }

        Action = "sts:AssumeRole"

        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }

          ArnLike = {
            "aws:SourceArn" = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"
          }
        }
      }
    ]
  })

  tags = {
    Name  = "peter-poc-vpc-flow-logs-role"
    email = var.owner_email
  }
}


############################################
# IAM Permissions
#
# Flow Logs service writes only to
# the dedicated CloudWatch Log Group.
############################################

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "peter-poc-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      #
      # Write logs into the dedicated
      # VPC Flow Logs log group
      #
      {
        Sid    = "WriteVPCFlowLogs"
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]

        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      },

      #
      # DescribeLogGroups does not support
      # useful resource-level restriction.
      #
      {
        Sid    = "DescribeLogGroups"
        Effect = "Allow"

        Action = [
          "logs:DescribeLogGroups"
        ]

        Resource = "*"
      }
    ]
  })
}


############################################
# VPC Flow Log
############################################

resource "aws_flow_log" "vpc" {
  vpc_id = aws_vpc.main.id

  traffic_type = "ALL"

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  #
  # Faster operational / security visibility
  #
  max_aggregation_interval = 60

  #
  # Enhanced custom format
  #
  # IMPORTANT:
  # "$${...}" escapes Terraform interpolation
  # so AWS receives "${...}".
  #
  log_format = join(" ", [
    "$${version}",
    "$${account-id}",
    "$${interface-id}",
    "$${srcaddr}",
    "$${dstaddr}",
    "$${srcport}",
    "$${dstport}",
    "$${protocol}",
    "$${packets}",
    "$${bytes}",
    "$${start}",
    "$${end}",
    "$${action}",
    "$${log-status}",
    "$${vpc-id}",
    "$${subnet-id}",
    "$${instance-id}",
    "$${tcp-flags}",
    "$${type}",
    "$${pkt-srcaddr}",
    "$${pkt-dstaddr}",
    "$${region}",
    "$${az-id}",
    "$${flow-direction}",
    "$${traffic-path}"
  ])

  tags = {
    Name  = "peter-poc-vpc-flow-logs"
    email = var.owner_email
  }

  #
  # Ensure IAM permissions exist before
  # Flow Log creation.
  #
  depends_on = [
    aws_iam_role_policy.vpc_flow_logs
  ]
}


############################################
# Outputs
############################################

output "vpc_flow_log_id" {
  description = "VPC Flow Log ID"
  value       = aws_flow_log.vpc.id
}

output "vpc_flow_log_group_name" {
  description = "CloudWatch Log Group for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.vpc_flow_logs.name
}

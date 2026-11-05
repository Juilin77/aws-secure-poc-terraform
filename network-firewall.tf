############################################
# AWS Network Firewall - Phase 1
#
# Purpose:
# - Deploy Network Firewall into existing VPC
# - Create dedicated firewall subnets in 2 AZs
# - Create firewall policy
# - Enable CloudWatch logging
#
# IMPORTANT:
# - Phase 1 does NOT change traffic routing
# - Existing ALB traffic remains unchanged
############################################


############################################
# Dedicated Firewall Subnets
############################################

resource "aws_subnet" "firewall_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.firewall_subnet_a_cidr
  availability_zone = var.availability_zone_a

  map_public_ip_on_launch = false

  tags = {
    Name = "peter-poc-firewall-subnet-a"
    Tier = "Firewall"
  }
}

resource "aws_subnet" "firewall_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.firewall_subnet_b_cidr
  availability_zone = var.availability_zone_b

  map_public_ip_on_launch = false

  tags = {
    Name = "peter-poc-firewall-subnet-b"
    Tier = "Firewall"
  }
}


############################################
# Firewall Policy
#
# Phase 1 = PASS
#
# Traffic is not routed through the firewall
# yet. Enforcement rules will be introduced
# during Phase 2 routing implementation.
############################################

resource "aws_networkfirewall_firewall_policy" "main" {
  name        = "peter-poc-firewall-policy"
  description = "Peter POC AWS Network Firewall policy"

  firewall_policy {
    stateless_default_actions = [
      "aws:pass"
    ]

    stateless_fragment_default_actions = [
      "aws:pass"
    ]

    stateless_rule_group_reference {
      priority     = 100
      resource_arn = aws_networkfirewall_rule_group.poc_web.arn
    }
  }

  tags = {
    Name = "peter-poc-firewall-policy"
  }
}


############################################
# AWS Network Firewall
############################################

resource "aws_networkfirewall_firewall" "main" {
  name                = "peter-poc-network-firewall"
  description         = "AWS Network Firewall for Peter POC"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn
  vpc_id              = aws_vpc.main.id

  subnet_mapping {
    subnet_id = aws_subnet.firewall_a.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.firewall_b.id
  }

  #
  # Keep protection disabled for this POC
  # so terraform destroy remains repeatable.
  #
  delete_protection                 = false
  firewall_policy_change_protection = false
  subnet_change_protection          = false

  tags = {
    Name = "peter-poc-network-firewall"
  }
}


############################################
# Network Firewall Log Groups
############################################

resource "aws_cloudwatch_log_group" "network_firewall_flow" {
  name              = "/aws/network-firewall/peter-poc/flow"
  retention_in_days = 90

  tags = {
    Name = "peter-poc-network-firewall-flow"
  }
}

resource "aws_cloudwatch_log_group" "network_firewall_alert" {
  name              = "/aws/network-firewall/peter-poc/alert"
  retention_in_days = 90

  tags = {
    Name = "peter-poc-network-firewall-alert"
  }
}


############################################
# Network Firewall Logging
############################################

resource "aws_networkfirewall_logging_configuration" "main" {
  firewall_arn = aws_networkfirewall_firewall.main.arn

  logging_configuration {

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall_flow.name
      }

      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.network_firewall_alert.name
      }

      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }
  }
}


############################################
# Outputs
############################################

output "network_firewall_arn" {
  description = "AWS Network Firewall ARN"
  value       = aws_networkfirewall_firewall.main.arn
}

output "network_firewall_status" {
  description = "AWS Network Firewall status"
  value       = aws_networkfirewall_firewall.main.firewall_status
}

output "firewall_subnet_a_id" {
  description = "Network Firewall subnet A"
  value       = aws_subnet.firewall_a.id
}

output "firewall_subnet_b_id" {
  description = "Network Firewall subnet B"
  value       = aws_subnet.firewall_b.id
}

############################################
# POC Stateless Rule Group
#
# Demo rules:
# - Allow HTTP 80
# - Allow HTTPS 443
#
# NOTE:
# Traffic is NOT routed through the
# firewall yet in Phase 1.
############################################

resource "aws_networkfirewall_rule_group" "poc_web" {
  capacity    = 100
  name        = "peter-poc-web-rule-group"
  description = "POC stateless rules for HTTP and HTTPS"
  type        = "STATELESS"

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {

        stateless_rule {
          priority = 100

          rule_definition {
            actions = ["aws:pass"]

            match_attributes {
              protocols = [6]

              source {
                address_definition = "0.0.0.0/0"
              }

              destination {
                address_definition = "0.0.0.0/0"
              }

              destination_port {
                from_port = 80
                to_port   = 80
              }
            }
          }
        }

        stateless_rule {
          priority = 110

          rule_definition {
            actions = ["aws:pass"]

            match_attributes {
              protocols = [6]

              source {
                address_definition = "0.0.0.0/0"
              }

              destination {
                address_definition = "0.0.0.0/0"
              }

              destination_port {
                from_port = 443
                to_port   = 443
              }
            }
          }
        }

      }
    }
  }

  tags = {
    Name = "peter-poc-web-rule-group"
  }
}
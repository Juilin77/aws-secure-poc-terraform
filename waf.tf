############################################
# AWS WAFv2
#
# Protected Resource:
# - alb-peter-vpc1-reverse-proxy
#
# Initial rollout:
# - Managed rules in COUNT mode
# - Default action ALLOW
#
# After validation:
# - Change override_action from count to none
############################################


############################################
# WAF Web ACL
############################################

resource "aws_wafv2_web_acl" "main" {
  name        = "waf-peter-vpc1-web-01"
  description = "AWS WAF baseline protection for Peter POC ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }


  ##########################################
  # Rule 1
  # Amazon IP Reputation List
  #
  # WCU: 25
  ##########################################

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf-peter-vpc1-ip-reputation-01"
      sampled_requests_enabled   = true
    }
  }


  ##########################################
  # Rule 2
  # AWS Core Rule Set
  #
  # General web application protection
  #
  # WCU: 700
  ##########################################

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf-peter-vpc1-common-rules-01"
      sampled_requests_enabled   = true
    }
  }


  ##########################################
  # Rule 3
  # Known Bad Inputs
  #
  # WCU: 200
  ##########################################

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "waf-peter-vpc1-known-bad-inputs-01"
      sampled_requests_enabled   = true
    }
  }


  ##########################################
  # Web ACL monitoring
  ##########################################

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf-peter-vpc1-web-01"
    sampled_requests_enabled   = true
  }


  tags = {
    Name = "waf-peter-vpc1-web-01"
  }
}


############################################
# Associate WAF with ALB
############################################

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}


############################################
# Outputs
############################################

output "waf_web_acl_arn" {
  description = "AWS WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.main.arn
}

output "waf_web_acl_name" {
  description = "AWS WAF Web ACL name"
  value       = aws_wafv2_web_acl.main.name
}

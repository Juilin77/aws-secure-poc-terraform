############################################
# CloudWatch Alarm Baseline
#
# Scope:
# - ALB 5XX
# - Target 5XX
# - Unhealthy targets
# - EC2 status check failure
#
# No SNS yet
############################################


############################################
# Local dimensions
############################################

locals {
  alb_dimension = aws_lb.main.arn_suffix

  target_group_dimension = aws_lb_target_group.app_https.arn_suffix
}


############################################
# ALB-generated 5XX
#
# Examples:
# - 500
# - 502
# - 503
# - 504
############################################

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "peter-poc-alb-5xx"
  alarm_description   = "ALB generated HTTP 5XX responses detected"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods  = 1
  datapoints_to_alarm = 1

  metric_name = "HTTPCode_ELB_5XX_Count"
  namespace   = "AWS/ApplicationELB"

  period    = 300
  statistic = "Sum"

  threshold = 0

  dimensions = {
    LoadBalancer = local.alb_dimension
  }

  treat_missing_data = "notBreaching"

  tags = {
    Name = "peter-poc-alb-5xx"
  }

  alarm_actions = [aws_sns_topic.poc_alerts.arn]
  ok_actions    = [aws_sns_topic.poc_alerts.arn]

}


############################################
# Target-generated 5XX
#
# Application/backend generated errors
############################################

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "peter-poc-target-5xx"
  alarm_description   = "Backend target generated HTTP 5XX responses detected"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods  = 1
  datapoints_to_alarm = 1

  metric_name = "HTTPCode_Target_5XX_Count"
  namespace   = "AWS/ApplicationELB"

  period    = 300
  statistic = "Sum"

  threshold = 0

  dimensions = {
    LoadBalancer = local.alb_dimension
    TargetGroup  = local.target_group_dimension
  }

  treat_missing_data = "notBreaching"

  tags = {
    Name = "peter-poc-target-5xx"
  }

  alarm_actions = [aws_sns_topic.poc_alerts.arn]
  ok_actions    = [aws_sns_topic.poc_alerts.arn]
}


############################################
# Unhealthy Target
#
# Current POC has one EC2 target.
# Any unhealthy target is significant.
############################################

resource "aws_cloudwatch_metric_alarm" "unhealthy_target" {
  alarm_name          = "peter-poc-unhealthy-target"
  alarm_description   = "One or more ALB targets are unhealthy"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods  = 2
  datapoints_to_alarm = 2

  metric_name = "UnHealthyHostCount"
  namespace   = "AWS/ApplicationELB"

  period    = 60
  statistic = "Minimum"

  threshold = 0

  dimensions = {
    LoadBalancer = local.alb_dimension
    TargetGroup  = local.target_group_dimension
  }

  treat_missing_data = "breaching"

  tags = {
    Name = "peter-poc-unhealthy-target"
  }

  alarm_actions = [aws_sns_topic.poc_alerts.arn]
  ok_actions    = [aws_sns_topic.poc_alerts.arn]
}


############################################
# EC2 Status Check Failed
#
# Covers underlying system and
# instance-level status failures.
############################################

resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  alarm_name          = "peter-poc-ec2-status-check-failed"
  alarm_description   = "EC2 instance or underlying system status check failed"
  comparison_operator = "GreaterThanThreshold"

  evaluation_periods  = 2
  datapoints_to_alarm = 2

  metric_name = "StatusCheckFailed"
  namespace   = "AWS/EC2"

  period    = 60
  statistic = "Maximum"

  threshold = 0

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  treat_missing_data = "missing"

  tags = {
    Name = "peter-poc-ec2-status-check-failed"
  }

  alarm_actions = [aws_sns_topic.poc_alerts.arn]
  ok_actions    = [aws_sns_topic.poc_alerts.arn]
}


############################################
# Outputs
############################################

output "cloudwatch_alarm_names" {
  description = "CloudWatch alarm baseline"
  value = [
    aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_target.alarm_name,
    aws_cloudwatch_metric_alarm.ec2_status_check_failed.alarm_name
  ]
}

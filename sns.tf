############################################
# SNS Topic for Peter POC Alerts
############################################

resource "aws_sns_topic" "poc_alerts" {
  name = "peter-poc-alerts"

  tags = {
    Name = "peter-poc-alerts"
  }
}

############################################
# Email Subscription
############################################

resource "aws_sns_topic_subscription" "poc_alerts_email" {
  topic_arn = aws_sns_topic.poc_alerts.arn
  protocol  = "email"
  endpoint  = var.owner_email
}

############################################
# Outputs
############################################

output "poc_alerts_sns_topic_arn" {
  description = "SNS topic ARN for Peter POC CloudWatch alarms"
  value       = aws_sns_topic.poc_alerts.arn
}

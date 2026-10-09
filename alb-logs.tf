############################################
# ALB Access Logs
############################################

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "peter-poc-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "peter-poc-alb-logs"
  }
}


############################################
# Block Public Access
############################################

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}


############################################
# SSE-S3 Encryption
#
# ALB traditional access logs support SSE-S3
############################################

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


############################################
# Bucket Ownership
############################################

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


############################################
# Lifecycle
#
# POC baseline:
# keep ALB logs for 90 days
############################################

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-alb-access-logs"
    status = "Enabled"

    filter {
      prefix = "alb-access-logs/"
    }

    expiration {
      days = 90
    }
  }
}


############################################
# Bucket Policy for ALB Log Delivery
############################################

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"

        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }

        Action = "s3:PutObject"

        Resource = "${aws_s3_bucket.alb_logs.arn}/alb-access-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"

        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"
          }
        }
      }
    ]
  })
}


############################################
# Enable Access Logs on ALB
############################################

# Add this access_logs block inside your existing aws_lb.main
#
# DO NOT create another aws_lb.main resource.
############################################

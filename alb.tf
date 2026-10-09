resource "aws_security_group" "alb" {
  name        = "peter-poc-alb-sg"
  description = "Security group for Peter POC Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from Internet for HTTPS redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    description = "Allow HTTPS to application targets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "peter-poc-alb-sg"
  }
}

resource "aws_lb" "main" {
  name               = "peter-poc-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb-access-logs"
    enabled = true
  }

  tags = {
    Name = "peter-poc-alb"
  }

  depends_on = [
    aws_s3_bucket_policy.alb_logs
  ]
}

#
# New HTTPS target group
#
resource "aws_lb_target_group" "app_https" {
  name        = "peter-poc-app-https-tg"
  port        = 443
  protocol    = "HTTPS"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTPS"
    matcher             = "200-399"
  }

  tags = {
    Name = "peter-poc-app-https-tg"
  }
}

resource "aws_lb_target_group_attachment" "app_https" {
  target_group_arn = aws_lb_target_group.app_https.arn
  target_id        = aws_instance.app.id
  port             = 443
}

#
# HTTP 80 -> HTTPS 443 redirect
#
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

#
# HTTPS 443 -> HTTPS target group 443
#
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"

  certificate_arn = aws_acm_certificate_validation.poc.certificate_arn
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_https.arn
  }
}

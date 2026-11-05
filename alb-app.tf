##########################################
# Internal Application Load Balancer
# App Tier
#
# Traffic flow:
#
# EC2-Web
#    ↓ HTTPS/443
# Internal ALB-App
#    ↓ HTTPS/443
# EC2-App
##########################################


##########################################
# ALB-App Security Group
##########################################

resource "aws_security_group" "alb_app" {
  name        = "alb-app-sg"
  description = "Security Group for internal App Tier ALB"
  vpc_id      = aws_vpc.main.id

  ################################
  # Inbound
  #
  # Only Web Tier may access
  # the App ALB.
  ################################

  ingress {
    description     = "HTTPS from Web Tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  ################################
  # Outbound
  #
  # ALB forwards HTTPS traffic
  # to App Tier.
  #
  # CIDR used to avoid inline SG
  # circular dependency.
  ################################

  egress {
    description = "HTTPS to App Tier"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  tags = {
    Name = "alb-app-sg"
  }
}


##########################################
# Internal ALB-App
##########################################

resource "aws_lb" "app" {
  name               = "alb-app"
  internal           = true
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_app.id
  ]

  subnets = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "alb-app"
    Tier = "App"
  }
}


##########################################
# App Target Group
##########################################

resource "aws_lb_target_group" "app_internal_https" {
  name = "alb-app-https-tg"

  port        = 443
  protocol    = "HTTPS"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  ################################
  # Health Check
  ################################

  health_check {
    enabled = true

    protocol = "HTTPS"
    port     = "443"
    path     = "/"

    matcher = "200-399"

    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "alb-app-https-tg"
    Tier = "App"
  }
}


##########################################
# Attach EC2-App to Target Group
##########################################

resource "aws_lb_target_group_attachment" "app_internal_https" {
  target_group_arn = aws_lb_target_group.app_internal_https.arn

  target_id = aws_instance.app.id
  port      = 443
}


##########################################
# HTTPS Listener
##########################################

resource "aws_lb_listener" "app_https" {
  load_balancer_arn = aws_lb.app.arn

  port     = 443
  protocol = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  certificate_arn = aws_acm_certificate.poc.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_internal_https.arn
  }
}


##########################################
# Outputs
##########################################

output "alb_app_dns_name" {
  description = "Internal DNS name of App Tier ALB"
  value       = aws_lb.app.dns_name
}

output "alb_app_target_group_arn" {
  description = "Target Group ARN for App Tier ALB"
  value       = aws_lb_target_group.app_internal_https.arn
}

output "alb_app_security_group_id" {
  description = "Security Group ID for App Tier ALB"
  value       = aws_security_group.alb_app.id
}
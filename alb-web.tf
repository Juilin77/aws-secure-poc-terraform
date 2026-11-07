##########################################
# Internal Application Load Balancer
# Web Tier
#
# Traffic flow:
#
# Reverse Proxy
#      ↓ HTTPS/443
# Internal ALB-Web
#      ↓ HTTPS/443
# EC2-Web
##########################################


##########################################
# ALB-Web Security Group
##########################################

resource "aws_security_group" "alb_web" {
  name        = "alb-web-sg"
  description = "Security group for Peter POC internal Web ALB"
  vpc_id      = aws_vpc.main.id

  ################################
  # Inbound
  #
  # Only Reverse Proxy may access
  # the Web ALB.
  ################################

  ingress {
    description     = "HTTPS from Reverse Proxy"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.reverse_proxy.id]
  }

  ################################
  # Outbound
  #
  # ALB forwards HTTPS traffic
  # only to EC2-Web.
  ################################

  egress {
    description = "HTTPS to Web Tier"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  tags = {
    Name = "alb-web-sg"
  }
}


##########################################
# Internal ALB-Web
##########################################

resource "aws_lb" "web" {
  name               = "alb-web"
  internal           = true
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb_web.id
  ]

  subnets = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "alb-web"
    Tier = "Web"
  }
}


##########################################
# Web Target Group
##########################################

resource "aws_lb_target_group" "web_https" {
  name = "alb-web-https-tg"

  port     = 443
  protocol = "HTTPS"

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
    Name = "alb-web-https-tg"
    Tier = "Web"
  }
}


##########################################
# Attach EC2-Web to Target Group
##########################################

resource "aws_lb_target_group_attachment" "web_https" {
  target_group_arn = aws_lb_target_group.web_https.arn

  target_id = aws_instance.web.id
  port      = 443
}


##########################################
# HTTPS Listener
##########################################

resource "aws_lb_listener" "web_https" {
  load_balancer_arn = aws_lb.web.arn

  port     = 443
  protocol = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  certificate_arn = aws_acm_certificate.poc.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_https.arn
  }
}


##########################################
# Outputs
##########################################

output "alb_web_dns_name" {
  description = "Internal DNS name of Web Tier ALB"
  value       = aws_lb.web.dns_name
}

output "alb_web_target_group_arn" {
  description = "Target Group ARN for Web Tier ALB"
  value       = aws_lb_target_group.web_https.arn
}

output "alb_web_security_group_id" {
  description = "Security Group ID for Web Tier ALB"
  value       = aws_security_group.alb_web.id
}
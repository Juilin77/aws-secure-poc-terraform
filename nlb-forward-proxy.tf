##########################################
# Internal NLB - Forward Proxy
#
# Forward-proxy traffic on TCP/3128 must support
# methods such as HTTP CONNECT. Use a Layer-4 NLB
# rather than an ALB so the load balancer does not
# interpret the proxy protocol at Layer 7.
##########################################

resource "aws_security_group" "nlb_forward_proxy" {
  name        = "peter-vpc1-nlb-forward-proxy-01-sg"
  description = "Security group for internal Forward Proxy NLB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "sg-peter-vpc1-nlb-forward-proxy-01"
  }
}

# Workloads -> Forward Proxy NLB TCP/3128.
# Security-group references keep the NLB reachable only
# from approved workload tiers rather than whole subnets.
resource "aws_security_group_rule" "nlb_forward_proxy_from_app" {
  type                     = "ingress"
  description              = "Allow TCP/3128 from App tier"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nlb_forward_proxy.id
  source_security_group_id = aws_security_group.app.id
}

resource "aws_security_group_rule" "nlb_forward_proxy_from_web" {
  type                     = "ingress"
  description              = "Allow TCP/3128 from Web tier"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nlb_forward_proxy.id
  source_security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule" "nlb_forward_proxy_from_repo" {
  type                     = "ingress"
  description              = "Allow TCP/3128 from Repository server"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nlb_forward_proxy.id
  source_security_group_id = aws_security_group.repo.id
}

resource "aws_security_group_rule" "nlb_forward_proxy_from_ad" {
  type                     = "ingress"
  description              = "Allow TCP/3128 from Active Directory server"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nlb_forward_proxy.id
  source_security_group_id = aws_security_group.ad.id
}

resource "aws_security_group_rule" "nlb_forward_proxy_from_wsus" {
  type                     = "ingress"
  description              = "Allow TCP/3128 from WSUS server"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nlb_forward_proxy.id
  source_security_group_id = aws_security_group.wsus.id
}

resource "aws_security_group_rule" "nlb_forward_proxy_to_proxy" {
  type                     = "egress"
  description              = "Allow TCP/3128 to Forward Proxy EC2"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nlb_forward_proxy.id
  source_security_group_id = aws_security_group.forward_proxy.id
}

# Forward Proxy EC2 accepts proxy traffic only from the NLB.
resource "aws_security_group_rule" "forward_proxy_from_nlb" {
  type                     = "ingress"
  description              = "Allow TCP/3128 from Forward Proxy NLB only"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.forward_proxy.id
  source_security_group_id = aws_security_group.nlb_forward_proxy.id
}

resource "aws_lb" "forward_proxy" {
  name               = "nlb-peter-vpc1-forward-proxy"
  internal           = true
  load_balancer_type = "network"

  security_groups = [
    aws_security_group.nlb_forward_proxy.id
  ]

  subnets = [
    aws_subnet.forward_proxy_a.id,
    aws_subnet.forward_proxy_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "nlb-peter-vpc1-forward-proxy"
    Tier = "ForwardProxy"
  }
}

resource "aws_lb_target_group" "forward_proxy" {
  name        = "tg-peter-vpc1-forward-proxy-01"
  port        = 3128
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "tg-peter-vpc1-forward-proxy-01"
    Tier = "ForwardProxy"
  }
}

resource "aws_lb_target_group_attachment" "forward_proxy" {
  target_group_arn = aws_lb_target_group.forward_proxy.arn
  target_id        = aws_instance.forward_proxy.id
  port             = 3128
}

resource "aws_lb_listener" "forward_proxy" {
  load_balancer_arn = aws_lb.forward_proxy.arn
  port              = 3128
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.forward_proxy.arn
  }
}

output "nlb_forward_proxy_dns_name" {
  description = "Internal DNS name of Forward Proxy NLB"
  value       = aws_lb.forward_proxy.dns_name
}

output "nlb_forward_proxy_target_group_arn" {
  description = "Target Group ARN for Forward Proxy NLB"
  value       = aws_lb_target_group.forward_proxy.arn
}


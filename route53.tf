resource "aws_route53_record" "poc_alb" {
  zone_id = "Z0916808EDFB6QNJTP1V"
  name    = "poc.ipursuitlab.com"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

############################################
# VPC-1 Internal Repository DNS
############################################

resource "aws_route53_zone" "vpc1_internal" {
  name = "vpc1.internal"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_route53_record" "vpc1_repo" {
  zone_id = aws_route53_zone.vpc1_internal.zone_id
  name    = "repo.vpc1.internal"
  type    = "A"
  ttl     = 60

  records = [
    aws_instance.repo.private_ip
  ]
}
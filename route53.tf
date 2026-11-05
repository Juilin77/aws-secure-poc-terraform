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

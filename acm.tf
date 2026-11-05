resource "aws_acm_certificate" "poc" {
  domain_name       = "poc.ipursuitlab.com"
  validation_method = "DNS"

  tags = {
    Name = "peter-poc-acm"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.poc.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = "Z0916808EDFB6QNJTP1V"
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "poc" {
  certificate_arn = aws_acm_certificate.poc.arn

  validation_record_fqdns = [
    for record in aws_route53_record.acm_validation : record.fqdn
  ]
}

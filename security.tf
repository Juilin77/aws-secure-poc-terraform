resource "aws_security_group" "ec2_private" {
  name        = "peter-poc-ec2-private-sg"
  description = "Security group for private EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTPS from ALB only"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Allow SSH from EC2 Instance Connect Endpoint only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  tags = {
    Name = "peter-poc-ec2-private-sg"
  }
}

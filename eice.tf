resource "aws_security_group" "eice" {
  name        = "peter-poc-eice-sg"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow SSH to private subnet A"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  tags = {
    Name = "peter-poc-eice-sg"
  }
}

resource "aws_ec2_instance_connect_endpoint" "main" {
  subnet_id          = aws_subnet.private_a.id
  security_group_ids = [aws_security_group.eice.id]

  preserve_client_ip = false

  tags = {
    Name = "peter-poc-eice"
  }
}

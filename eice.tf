resource "aws_security_group" "eice" {
  name        = "peter-vpc1-eice-01-sg"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow SSH to private subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      var.private_subnet_a_cidr,
      var.private_subnet_b_cidr
    ]
  }

  egress {
    description = "Allow SSH to NAT subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      var.nat_subnet_a_cidr,
      var.nat_subnet_b_cidr
    ]
  }

  egress {
    description = "Allow SSH to Forward Proxy subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      var.forward_proxy_subnet_a_cidr,
      var.forward_proxy_subnet_b_cidr
    ]
  }

  egress {
    description = "Allow SSH to Repo subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      var.repo_subnet_a_cidr,
      var.repo_subnet_b_cidr
    ]
  }

  egress {
    description = "Allow RDP to Windows servers in private subnet"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [
      var.private_subnet_a_cidr,
      var.private_subnet_b_cidr
    ]
  }

  tags = {
    Name = "sg-peter-vpc1-eice-01"
  }
}

resource "aws_ec2_instance_connect_endpoint" "main" {
  subnet_id          = aws_subnet.private_a.id
  security_group_ids = [aws_security_group.eice.id]

  preserve_client_ip = false

  tags = {
    Name = "eice-peter-vpc1-01"
  }
}


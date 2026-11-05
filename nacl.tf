############################################
# Public NACL
# Associated with:
# - Public Subnet A 10.10.1.0/24
# - Public Subnet B 10.10.2.0/24
############################################

resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-public-nacl"
  }
}

#
# PUBLIC NACL - INBOUND
#

# HTTP 80 is required only for redirect to HTTPS
resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# HTTPS from Internet to ALB
resource "aws_network_acl_rule" "public_in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# Return traffic from private EC2 to ALB nodes
resource "aws_network_acl_rule" "public_in_ephemeral_from_private_a" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 1024
  to_port        = 65535
}

#
# PUBLIC NACL - OUTBOUND
#

# ALB -> EC2 HTTPS backend
resource "aws_network_acl_rule" "public_out_https_private_a" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 443
  to_port        = 443
}

# ALB responses to Internet clients
resource "aws_network_acl_rule" "public_out_ephemeral_internet" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

#
# PUBLIC SUBNET ASSOCIATIONS
#

resource "aws_network_acl_association" "public_a" {
  network_acl_id = aws_network_acl.public.id
  subnet_id      = aws_subnet.public_a.id
}

resource "aws_network_acl_association" "public_b" {
  network_acl_id = aws_network_acl.public.id
  subnet_id      = aws_subnet.public_b.id
}


############################################
# Private NACL
# Associated with:
# - Private Subnet A 10.10.11.0/24
# - Private Subnet B 10.10.12.0/24
############################################

resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-private-nacl"
  }
}

#
# PRIVATE NACL - INBOUND
#

# ALB Public Subnet A -> EC2 HTTPS
resource "aws_network_acl_rule" "private_in_https_public_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = 443
  to_port        = 443
}

# ALB Public Subnet B -> EC2 HTTPS
resource "aws_network_acl_rule" "private_in_https_public_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_b_cidr
  from_port      = 443
  to_port        = 443
}
resource "aws_network_acl_rule" "private_in_ephemeral_nat" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.nat_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_in_ephemeral_forward_proxy" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_in_ephemeral_forward_proxy_traffic" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 140
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_in_mysql_from_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 150
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr

  from_port = 3306
  to_port   = 3306
}

resource "aws_network_acl_rule" "private_in_ephemeral_from_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 160
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_b_cidr

  from_port = 1024
  to_port   = 65535
}

#
# EICE and EC2 are currently in Private Subnet A.
# Same-subnet traffic does not cross the subnet NACL boundary,
# so Security Group remains the primary control for TCP/22.
#
# If EICE is later placed in another subnet, add an explicit
# TCP/22 NACL rule for that source subnet.
#

#
# PRIVATE NACL - OUTBOUND
#

# EC2 responses to ALB nodes
resource "aws_network_acl_rule" "private_out_ephemeral_public_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_out_ephemeral_public_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_b_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_out_ssh_nat" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.nat_subnet_a_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "private_out_ssh_forward_proxy" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 130
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_a_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "private_out_forward_proxy" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 140
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_a_cidr
  from_port      = 3128
  to_port        = 3128
}

resource "aws_network_acl_rule" "private_out_mysql_to_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 150
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_b_cidr

  from_port = 3306
  to_port   = 3306
}

resource "aws_network_acl_rule" "private_out_ephemeral_to_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 160
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr

  from_port = 1024
  to_port   = 65535
}

#
# PRIVATE SUBNET ASSOCIATIONS
#

resource "aws_network_acl_association" "private_a" {
  network_acl_id = aws_network_acl.private.id
  subnet_id      = aws_subnet.private_a.id
}

resource "aws_network_acl_association" "private_b" {
  network_acl_id = aws_network_acl.private.id
  subnet_id      = aws_subnet.private_b.id
}

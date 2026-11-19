############################################
# Public NACL
# Associated with:
# - Public Subnet A 10.10.1.0/24
# - Public Subnet B 10.10.2.0/24
############################################

resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "nacl-peter-vpc1-public-01"
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
  cidr_block     = var.private_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "public_in_ephemeral_from_private_b" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 125
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_b_cidr
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
  cidr_block     = var.private_subnet_a_cidr
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_out_https_private_b" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 105
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_b_cidr
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
    Name = "nacl-peter-vpc1-private-01"
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
  cidr_block     = var.public_subnet_a_cidr
  from_port      = 443
  to_port        = 443
}

# ALB Public Subnet B -> EC2 HTTPS
resource "aws_network_acl_rule" "private_in_https_public_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 105
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_b_cidr
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "private_in_ephemeral_forward_proxy_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_in_ephemeral_forward_proxy_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 115
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_b_cidr
  from_port      = 1024
  to_port        = 65535
}

# Repo-A -> Private SSH/HTTPS return traffic
resource "aws_network_acl_rule" "private_in_ephemeral_repo_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.repo_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}

# Repo-B -> Private SSH/HTTPS return traffic
resource "aws_network_acl_rule" "private_in_ephemeral_repo_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 125
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.repo_subnet_b_cidr
  from_port      = 1024
  to_port        = 65535
}

# NAT -> EICE SSH return traffic
#
# EICE and EC2 are currently in Private Subnet A.
# Same-subnet traffic does not cross the subnet NACL boundary,
# so Security Group remains the primary control for TCP/22.
#
# If EICE is later placed in another subnet, add an explicit
# TCP/22 NACL rule for that source subnet.
#
resource "aws_network_acl_rule" "private_in_ephemeral_nat_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.nat_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}


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
  cidr_block     = var.public_subnet_a_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_out_ephemeral_public_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 105
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_b_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "private_out_ssh_forward_proxy_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_a_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "private_out_ssh_forward_proxy_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 115
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_b_cidr
  from_port      = 22
  to_port        = 22
}

# Private -> Repo-A HTTPS
resource "aws_network_acl_rule" "private_out_https_repo_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.repo_subnet_a_cidr
  from_port      = 443
  to_port        = 443
}

# Private -> Repo-B HTTPS
resource "aws_network_acl_rule" "private_out_https_repo_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 125
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.repo_subnet_b_cidr
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "private_out_ssh_nat_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 130
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.nat_subnet_a_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "private_out_ssh_nat_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 135
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.nat_subnet_b_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "private_out_forward_proxy_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 140
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_a_cidr
  from_port      = 3128
  to_port        = 3128
}

resource "aws_network_acl_rule" "private_out_forward_proxy_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 145
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.forward_proxy_subnet_b_cidr
  from_port      = 3128
  to_port        = 3128
}

# Private -> Repo-A SSH
resource "aws_network_acl_rule" "private_out_ssh_repo_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 150
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.repo_subnet_a_cidr
  from_port      = 22
  to_port        = 22
}

# Private -> Repo-B SSH
resource "aws_network_acl_rule" "private_out_ssh_repo_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 155
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.repo_subnet_b_cidr
  from_port      = 22
  to_port        = 22
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

############################################
# Private Subnet A <-> Private Subnet B
#
# POC design:
# Allow east-west traffic between the two
# private subnets at NACL level.
#
# Security Groups remain the primary
# stateful workload-level control.
############################################

resource "aws_network_acl_rule" "private_in_from_private_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 170
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_a_cidr
}

resource "aws_network_acl_rule" "private_in_from_private_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 180
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_b_cidr
}

resource "aws_network_acl_rule" "private_out_to_private_a" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 170
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_a_cidr
}

resource "aws_network_acl_rule" "private_out_to_private_b" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 180
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_b_cidr
}

############################################
# Internal Repo NACL
############################################

resource "aws_network_acl" "repo" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "nacl-peter-vpc1-repo-01"
  }
}

resource "aws_network_acl_association" "repo_a" {
  subnet_id      = aws_subnet.repo_a.id
  network_acl_id = aws_network_acl.repo.id
}

resource "aws_network_acl_association" "repo_b" {
  subnet_id      = aws_subnet.repo_b.id
  network_acl_id = aws_network_acl.repo.id
}

############################################
# Inbound
############################################

# EICE in Private Subnet A -> Repo SSH
resource "aws_network_acl_rule" "repo_in_ssh" {
  network_acl_id = aws_network_acl.repo.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_a_cidr
  from_port      = 22
  to_port        = 22
}

# Internal workloads and proxies -> Repo HTTPS
resource "aws_network_acl_rule" "repo_in_https" {
  for_each = {
    private_a = var.private_subnet_a_cidr
    private_b = var.private_subnet_b_cidr
    proxy_a   = var.forward_proxy_subnet_a_cidr
    proxy_b   = var.forward_proxy_subnet_b_cidr
  }

  network_acl_id = aws_network_acl.repo.id
  rule_number = 110 + index(
    ["private_a", "private_b", "proxy_a", "proxy_b"],
    each.key
  ) * 10
  egress      = false
  protocol    = "tcp"
  rule_action = "allow"
  cidr_block  = each.value
  from_port   = 443
  to_port     = 443
}

# Return traffic for outbound HTTPS / proxy requests
resource "aws_network_acl_rule" "repo_in_ephemeral" {
  network_acl_id = aws_network_acl.repo.id
  rule_number    = 160
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

############################################
# Outbound
############################################

# Repo -> AL2023 repository via NAT
resource "aws_network_acl_rule" "repo_out_https" {
  network_acl_id = aws_network_acl.repo.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# SSH / HTTPS responses to internal clients
resource "aws_network_acl_rule" "repo_out_ephemeral" {
  for_each = {
    private_a = var.private_subnet_a_cidr
    private_b = var.private_subnet_b_cidr
    proxy_a   = var.forward_proxy_subnet_a_cidr
    proxy_b   = var.forward_proxy_subnet_b_cidr
  }

  network_acl_id = aws_network_acl.repo.id
  rule_number = 110 + index(
    ["private_a", "private_b", "proxy_a", "proxy_b"],
    each.key
  ) * 10
  egress      = true
  protocol    = "tcp"
  rule_action = "allow"
  cidr_block  = each.value
  from_port   = 1024
  to_port     = 65535
}

# Retain existing Forward Proxy connectivity
resource "aws_network_acl_rule" "repo_out_proxy" {
  for_each = {
    proxy_a = var.forward_proxy_subnet_a_cidr
    proxy_b = var.forward_proxy_subnet_b_cidr
  }

  network_acl_id = aws_network_acl.repo.id
  rule_number    = each.key == "proxy_a" ? 160 : 170
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = each.value
  from_port      = 3128
  to_port        = 3128
}

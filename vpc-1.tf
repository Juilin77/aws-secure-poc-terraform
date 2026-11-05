resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "peter-poc-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-igw"
  }
}

# -----------------------------
# Public Subnets
# -----------------------------

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone_a
  map_public_ip_on_launch = false

  tags = {
    Name = "peter-poc-public-subnet-a"
    Tier = "Public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = var.availability_zone_b
  map_public_ip_on_launch = false

  tags = {
    Name = "peter-poc-public-subnet-b"
    Tier = "Public"
  }
}

# -----------------------------
# Private Subnets
# -----------------------------

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone_a

  tags = {
    Name = "peter-poc-private-subnet-a"
    Tier = "Private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = var.availability_zone_b

  tags = {
    Name = "peter-poc-private-subnet-b"
    Tier = "Private"
  }
}

# -----------------------------
# Public Route Table
# -----------------------------

############################################
# Network Firewall Endpoint Mapping
#
# Dynamically obtain endpoint IDs.
# Do NOT hard-code vpce-* IDs because they
# change after destroy / rebuild.
############################################

locals {
  network_firewall_endpoints = {
    for sync_state in aws_networkfirewall_firewall.main.firewall_status[0].sync_states :
    sync_state.availability_zone => sync_state.attachment[0].endpoint_id
  }
}


############################################
# Public Route Table - AZ A
#
# ALB subnet A -> Firewall endpoint A
############################################

resource "aws_route_table" "public_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-public-rt-a"
  }
}

resource "aws_route" "public_a_internet" {
  route_table_id         = aws_route_table.public_a.id
  destination_cidr_block = "0.0.0.0/0"

  vpc_endpoint_id = local.network_firewall_endpoints[var.availability_zone_a]
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_a.id
}


############################################
# Public Route Table - AZ B
#
# ALB subnet B -> Firewall endpoint B
############################################

resource "aws_route_table" "public_b" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-public-rt-b"
  }
}

resource "aws_route" "public_b_internet" {
  route_table_id         = aws_route_table.public_b.id
  destination_cidr_block = "0.0.0.0/0"

  vpc_endpoint_id = local.network_firewall_endpoints[var.availability_zone_b]
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_b.id
}

# -----------------------------
# Private Route Table
# -----------------------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------
# Default Security Group
# -----------------------------

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  ingress = []
  egress  = []

  tags = {
    Name = "peter-poc-default-sg-restricted"
  }
}

############################################
# Firewall Route Table - AZ A
#
# Firewall endpoint A -> IGW
############################################

resource "aws_route_table" "firewall_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-firewall-rt-a"
  }
}

resource "aws_route" "firewall_a_internet" {
  route_table_id         = aws_route_table.firewall_a.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "firewall_a" {
  subnet_id      = aws_subnet.firewall_a.id
  route_table_id = aws_route_table.firewall_a.id
}


############################################
# Firewall Route Table - AZ B
############################################

resource "aws_route_table" "firewall_b" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-firewall-rt-b"
  }
}

resource "aws_route" "firewall_b_internet" {
  route_table_id         = aws_route_table.firewall_b.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "firewall_b" {
  subnet_id      = aws_subnet.firewall_b.id
  route_table_id = aws_route_table.firewall_b.id
}
############################################
# Internet Gateway Route Table
#
# Internet -> Firewall -> ALB Public Subnets
############################################

resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-igw-rt"
  }
}

resource "aws_route_table_association" "igw" {
  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw.id
}


############################################
# IGW -> Public Subnet A via Firewall A
############################################

resource "aws_route" "igw_to_public_a" {
  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.public_subnet_cidr

  vpc_endpoint_id = local.network_firewall_endpoints[var.availability_zone_a]
}


############################################
# IGW -> Public Subnet B via Firewall B
############################################

resource "aws_route" "igw_to_public_b" {
  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.public_subnet_b_cidr

  vpc_endpoint_id = local.network_firewall_endpoints[var.availability_zone_b]
}

resource "aws_route" "igw_to_nat_a" {
  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.nat_subnet_a_cidr

  vpc_endpoint_id = local.network_firewall_endpoints[
    var.availability_zone_a
  ]
}
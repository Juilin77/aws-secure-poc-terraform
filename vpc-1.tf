resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-peter-vpc1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw-peter-vpc1"
  }
}

# -----------------------------
# Public Subnets
# -----------------------------

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = var.availability_zone_a
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-peter-vpc1-public-1a"
    Tier = "Public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = var.availability_zone_b
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-peter-vpc1-public-1b"
    Tier = "Public"
  }
}

# -----------------------------
# Private Subnets
# -----------------------------

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = var.availability_zone_a

  tags = {
    Name = "subnet-peter-vpc1-private-1a"
    Tier = "Private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = var.availability_zone_b

  tags = {
    Name = "subnet-peter-vpc1-private-1b"
    Tier = "Private"
  }
}

resource "aws_subnet" "repo_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.repo_subnet_a_cidr
  availability_zone       = var.availability_zone_a
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-peter-vpc1-repo-1a"
    Tier = "Private"
  }
}

resource "aws_subnet" "repo_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.repo_subnet_b_cidr
  availability_zone       = var.availability_zone_b
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-peter-vpc1-repo-1b"
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
    Name = "rt-peter-vpc1-public-1a"
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
    Name = "rt-peter-vpc1-public-1b"
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
    Name = "rt-peter-vpc1-private-01"
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
    Name = "sg-peter-vpc1-default-restricted-01"
  }
}

# -----------------------------
# Internal Repo Route Tables
# -----------------------------

resource "aws_route_table" "repo_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "rt-peter-vpc1-repo-1a"
  }
}

resource "aws_route_table" "repo_b" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "rt-peter-vpc1-repo-1b"
  }
}

# -----------------------------
# Repo Route Table Associations
# -----------------------------

resource "aws_route_table_association" "repo_a" {
  subnet_id      = aws_subnet.repo_a.id
  route_table_id = aws_route_table.repo_a.id
}

resource "aws_route_table_association" "repo_b" {
  subnet_id      = aws_subnet.repo_b.id
  route_table_id = aws_route_table.repo_b.id
}


############################################
# Firewall Route Table - AZ A
#
# Firewall endpoint A -> IGW
############################################

resource "aws_route_table" "firewall_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "rt-peter-vpc1-firewall-1a"
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
    Name = "rt-peter-vpc1-firewall-1b"
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
    Name = "rt-peter-vpc1-igw-01"
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
  destination_cidr_block = var.public_subnet_a_cidr

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


resource "aws_route" "igw_to_nat_b" {
  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.nat_subnet_b_cidr

  vpc_endpoint_id = local.network_firewall_endpoints[
    var.availability_zone_b
  ]
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_a.id
}

output "public_subnet_b_id" {
  value = aws_subnet.public_b.id
}

output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}

output "private_subnet_b_id" {
  value = aws_subnet.private_b.id
}

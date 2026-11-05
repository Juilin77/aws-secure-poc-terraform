############################################
# Peter POC - NAT Instance
#
# Phase 1:
# - Dedicated NAT subnet
# - NAT EC2
# - Elastic IP
# - Source/Destination Check disabled
# - IP forwarding + NAT masquerade
#
# IMPORTANT:
# No existing workload/firewall routes are
# changed in this phase.
############################################


############################################
# Dedicated NAT Subnet - AZ A
############################################

resource "aws_subnet" "nat_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.nat_subnet_a_cidr
  availability_zone       = var.availability_zone_a
  map_public_ip_on_launch = false

  tags = {
    Name = "peter-poc-nat-subnet-a"
    Tier = "Egress"
  }
}


############################################
# NAT Subnet Route Table
#
# NAT Instance itself must be able to reach
# the Internet through the IGW.
############################################

resource "aws_route_table" "nat_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-nat-rt-a"
  }
}

resource "aws_route" "nat_a_internet" {
  route_table_id         = aws_route_table.nat_a.id
  destination_cidr_block = "0.0.0.0/0"

  vpc_endpoint_id = local.network_firewall_endpoints[
    var.availability_zone_a
  ]
}

resource "aws_route_table_association" "nat_a" {
  subnet_id      = aws_subnet.nat_a.id
  route_table_id = aws_route_table.nat_a.id
}


############################################
# NAT Instance Security Group
############################################

resource "aws_security_group" "nat_instance" {
  name        = "peter-poc-nat-instance-sg"
  description = "Security group for Peter POC NAT instance"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # Future egress traffic from VPC
  #
  # POC: allow traffic from VPC CIDR.
  # Later we can tighten this when the
  # Forward Proxy path is completed.
  ##########################################

  ingress {
    description = "Allow NAT traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  ##########################################
  # EICE management
  ##########################################

  ingress {
    description     = "Allow SSH from EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  ##########################################
  # Internet outbound
  ##########################################

  egress {
    description = "Allow outbound Internet traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "peter-poc-nat-instance-sg"
  }
}


############################################
# NAT Instance
############################################

resource "aws_instance" "nat" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.nat_a.id

  vpc_security_group_ids = [
    aws_security_group.nat_instance.id
  ]


  ##########################################
  # CRITICAL for NAT Instance
  ##########################################

  source_dest_check = false


  ##########################################
  # IMDSv2
  ##########################################

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }


  ##########################################
  # Encrypted disk
  ##########################################

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }


  ##########################################
  # NAT configuration
  ##########################################

  user_data = <<-EOF
#!/bin/bash
set -eux

################################
# Enable IPv4 forwarding
################################

cat > /etc/sysctl.d/99-peter-nat.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
SYSCTL

sysctl --system


################################
# Wait for Internet connectivity
################################

for i in $(seq 1 30); do
  if curl -s --connect-timeout 5 https://aws.amazon.com >/dev/null 2>&1; then
    break
  fi

  sleep 5
done


################################
# Install iptables if required
################################

if ! command -v iptables >/dev/null 2>&1; then
  dnf install -y iptables-services
fi


################################
# Detect primary network interface
################################

IFACE=$(ip route show default | awk '{print $5; exit}')

echo "Detected NAT interface: $IFACE"


################################
# NAT / MASQUERADE
################################

iptables -t nat -C POSTROUTING \
  -s ${var.vpc_cidr} \
  -o "$IFACE" \
  -j MASQUERADE \
2>/dev/null || \
iptables -t nat -A POSTROUTING \
  -s ${var.vpc_cidr} \
  -o "$IFACE" \
  -j MASQUERADE


################################
# Forwarding
################################

iptables -C FORWARD \
  -s ${var.vpc_cidr} \
  -j ACCEPT \
2>/dev/null || \
iptables -A FORWARD \
  -s ${var.vpc_cidr} \
  -j ACCEPT

iptables -C FORWARD \
  -d ${var.vpc_cidr} \
  -m state \
  --state ESTABLISHED,RELATED \
  -j ACCEPT \
2>/dev/null || \
iptables -A FORWARD \
  -d ${var.vpc_cidr} \
  -m state \
  --state ESTABLISHED,RELATED \
  -j ACCEPT


################################
# Persist rules
################################

if systemctl list-unit-files | grep -q iptables.service; then
  service iptables save || true
  systemctl enable iptables || true
fi
EOF


  tags = {
    Name = "peter-poc-nat-01"
    Tier = "Egress"
  }
}


############################################
# Elastic IP
############################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "peter-poc-nat-eip"
  }
}


############################################
# Associate EIP with NAT Instance
############################################

resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}


############################################
# Outputs
############################################

output "nat_instance_id" {
  description = "NAT instance ID"
  value       = aws_instance.nat.id
}

output "nat_instance_private_ip" {
  description = "NAT instance private IP"
  value       = aws_instance.nat.private_ip
}

output "nat_instance_public_ip" {
  description = "NAT instance Elastic IP"
  value       = aws_eip.nat.public_ip
}

output "nat_subnet_id" {
  description = "Dedicated NAT subnet ID"
  value       = aws_subnet.nat_a.id
}
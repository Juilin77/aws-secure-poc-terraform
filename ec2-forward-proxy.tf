############################################
# Peter VPC-1 - Forward Proxy (Squid)
############################################

############################################
# Forward Proxy Subnets
############################################
resource "aws_subnet" "forward_proxy_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.forward_proxy_subnet_a_cidr
  availability_zone       = var.availability_zone_a
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-peter-vpc1-forward-proxy-1a"
    Tier = "EgressProxy"
  }
}

resource "aws_subnet" "forward_proxy_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.forward_proxy_subnet_b_cidr
  availability_zone       = var.availability_zone_b
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-peter-vpc1-forward-proxy-1b"
    Tier = "EgressProxy"
  }
}

############################################
# Forward Proxy Route Tables
############################################
resource "aws_route_table" "forward_proxy_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "rt-peter-vpc1-forward-proxy-1a"
  }
}

resource "aws_route_table_association" "forward_proxy_a" {
  subnet_id      = aws_subnet.forward_proxy_a.id
  route_table_id = aws_route_table.forward_proxy_a.id
}

resource "aws_route_table" "forward_proxy_b" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "rt-peter-vpc1-forward-proxy-1b"
  }
}

resource "aws_route_table_association" "forward_proxy_b" {
  subnet_id      = aws_subnet.forward_proxy_b.id
  route_table_id = aws_route_table.forward_proxy_b.id
}


############################################
# Forward Proxy Security Group
# Standalone Rules Only
############################################

resource "aws_security_group" "forward_proxy" {
  name        = "peter-vpc1-ec2-forward-proxy-01-sg"
  description = "Security group for Peter VPC-1 forward proxy"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "sg-peter-vpc1-ec2-forward-proxy-01"
  }
}

############################################
# EICE -> Forward Proxy SSH
############################################

resource "aws_security_group_rule" "forward_proxy_ssh_from_eice" {
  type                     = "ingress"
  description              = "Allow SSH from EICE"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.forward_proxy.id
  source_security_group_id = aws_security_group.eice.id
}

############################################
# Forward Proxy -> Internet HTTP
############################################

resource "aws_security_group_rule" "forward_proxy_http_egress" {
  type              = "egress"
  description       = "Allow HTTP outbound"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.forward_proxy.id
  cidr_blocks       = ["0.0.0.0/0"]
}

############################################
# Forward Proxy -> Internet HTTPS
############################################

resource "aws_security_group_rule" "forward_proxy_https_egress" {
  type              = "egress"
  description       = "Allow HTTPS outbound"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.forward_proxy.id
  cidr_blocks       = ["0.0.0.0/0"]
}


############################################
# Forward Proxy EC2 - Squid
############################################
resource "aws_instance" "forward_proxy" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.forward_proxy_a.id

  vpc_security_group_ids = [
    aws_security_group.forward_proxy.id
  ]

  associate_public_ip_address = false
  user_data_replace_on_change = true

  # Squid is installed during first boot, so ensure the subnet has
  # its default route through the NAT instance before EC2 launches.
  depends_on = [
    aws_route.forward_proxy_internet,
    aws_route.repo_b_to_nat_a,
    aws_instance.repo,
    aws_route53_record.vpc1_repo
  ]

  # Require IMDSv2
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  # Encrypted Root Volume
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  ##########################################
  # Squid Explicit Forward Proxy
  # Listener : TCP/3128
  # HTTP     : allowed
  # HTTPS    : CONNECT tunnel to TCP/443
  # Cache    : disabled for predictable VPC-1
  #            behavior and lower disk usage
  ##########################################
  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              log() {
                echo "[$(date -Is)] $*"
              }

              log "Installing Squid from Internal Repo"

              ################################
              # Install trusted Repo certificate
              ################################

              mkdir -p /etc/pki/peter-repo

              cat > /etc/pki/peter-repo/ca.crt <<'CERT'
              ${file("${path.module}/repo-server.crt")}
              CERT

              chmod 0644 /etc/pki/peter-repo/ca.crt

              log "Configuring trusted internal AL2023 RPM repository"
              cat > /etc/yum.repos.d/peter-internal.repo <<'REPO'
              [peter-internal]
              name=Peter Internal AL2023 RPM Repository
              baseurl=https://${aws_route53_record.vpc1_repo.fqdn}/packages
              enabled=1
              gpgcheck=1
              repo_gpgcheck=0
              sslverify=1
              sslcacert=/etc/pki/peter-repo/ca.crt
              REPO

              # Wait until Internal Repository is ready
              REPO_URL="https://${aws_route53_record.vpc1_repo.fqdn}/packages/repodata/repomd.xml"

              READY=false
              for i in $(seq 1 60); do
                if curl --noproxy '*' -f -s \
                  --cacert /etc/pki/peter-repo/ca.crt \
                  --connect-timeout 5 \
                  --max-time 10 \
                  "$${REPO_URL}" \
                  -o /tmp/peter-repomd.xml &&
                  test -s /tmp/peter-repomd.xml; then
                  READY=true
                  break
                fi

                log "Waiting for Repository ($${i}/60)"
                sleep 10
              done

              if [ "$${READY}" != "true" ]; then
                log "ERROR: Repository not ready"
                exit 1
              fi

              log "Repository ready"

              dnf --disablerepo='*' --enablerepo=peter-internal \
                --setopt=install_weak_deps=False install -y squid

              log "Backing up vendor Squid configuration"
              if [ -f /etc/squid/squid.conf ] && [ ! -f /etc/squid/squid.conf.vendor ]; then
                cp -p /etc/squid/squid.conf /etc/squid/squid.conf.vendor
              fi

              log "Writing hardened VPC-1 Squid configuration"
              cat > /etc/squid/squid.conf <<'SQUID'
              # Peter VPC-1 - Squid explicit forward proxy
              http_port 3128

              visible_hostname ec2-peter-vpc1-forward-proxy-1a

              # Do not disclose Squid version in generated error pages.
              httpd_suppress_version_string on

              # Restrict destinations to standard web ports.
              acl SSL_ports port 443
              acl Safe_ports port 80
              acl Safe_ports port 443
              acl CONNECT method CONNECT

              http_access deny !Safe_ports
              http_access deny CONNECT !SSL_ports

              # Network access to port 3128 is restricted by the EC2 security group
              # and the Forward Proxy NLB security group rule in nlb-forward-proxy.tf.
              http_access allow all
              http_access deny all

              # Explicit forward proxy only; no transparent interception / SSL bump.
              cache deny all
              cache_mem 64 MB
              maximum_object_size 0 KB

              # Logging
              access_log stdio:/var/log/squid/access.log
              cache_log /var/log/squid/cache.log

              # Privacy: do not add a client X-Forwarded-For header.
              forwarded_for delete
              via off

              # Conservative connection timeouts.
              connect_timeout 10 seconds
              request_timeout 60 seconds
              read_timeout 5 minutes
              SQUID

              # Open local firewall only when firewalld is active.
              if systemctl is-active --quiet firewalld; then
                firewall-cmd --permanent --add-port=3128/tcp
                firewall-cmd --reload
              fi

              log "Validating Squid configuration"
              squid -k parse

              log "Enabling and starting Squid"
              systemctl enable squid
              systemctl restart squid

              log "Squid forward proxy bootstrap completed"
              EOF

  tags = {
    Name = "ec2-peter-vpc1-forward-proxy-1a"
    Tier = "ForwardProxy"
  }
}

############################################
# Forward Proxy -> NAT Instance
############################################
resource "aws_route" "forward_proxy_internet" {
  route_table_id         = aws_route_table.forward_proxy_a.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

resource "aws_route" "forward_proxy_b_internet" {
  route_table_id         = aws_route_table.forward_proxy_b.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

############################################
# Outputs
############################################
output "forward_proxy_instance_id" {
  description = "Peter VPC-1 forward proxy EC2 instance ID"
  value       = aws_instance.forward_proxy.id
}

output "forward_proxy_private_ip" {
  description = "Peter VPC-1 forward proxy private IP address"
  value       = aws_instance.forward_proxy.private_ip
}

output "forward_proxy_port" {
  description = "Squid explicit proxy port"
  value       = 3128
}

output "forward_proxy_subnet_b_id" {
  value = aws_subnet.forward_proxy_b.id
}

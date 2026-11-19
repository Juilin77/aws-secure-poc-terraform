############################################
# Peter VPC-1 - Reverse Proxy (Nginx)
############################################

############################################
# Reverse Proxy Security Group
############################################
resource "aws_security_group" "reverse_proxy" {
  name        = "peter-vpc1-ec2-reverse-proxy-01-sg"
  description = "Security group for Peter VPC-1 Nginx reverse proxy"
  vpc_id      = aws_vpc.main.id

  # ALB -> Reverse Proxy HTTPS
  ingress {
    description     = "Allow HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_reverse_proxy.id]
  }

  # EICE -> Reverse Proxy SSH
  ingress {
    description     = "Allow SSH from EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  # Reverse Proxy -> Internal Web ALB
  egress {
    description = "Allow HTTPS to internal Web ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_a_cidr,
      var.private_subnet_b_cidr
    ]
  }

  # Reverse Proxy -> Internal Repository
  egress {
    description = "HTTPS to internal AL2023 RPM repository"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [
      var.repo_subnet_a_cidr,
      var.repo_subnet_b_cidr
    ]
  }

  tags = {
    Name = "sg-peter-vpc1-ec2-reverse-proxy-01"
  }

}


############################################
# Reverse Proxy EC2 - Nginx
############################################
resource "aws_instance" "reverse_proxy" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.reverse_proxy.id
  ]

  associate_public_ip_address = false
  user_data_replace_on_change = true

  # Nginx is installed during first boot, so ensure the NAT instance,
  # internal Repository EC2, and DNS record are created before EC2 launches.
  # The User Data readiness check waits for the Repository HTTPS service.
  depends_on = [
    aws_route.repo_b_to_nat_a,
    aws_instance.repo,
    aws_route53_record.vpc1_repo,
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
  # Nginx HTTPS Reverse Proxy
  #
  # Front-end : HTTPS/443
  # Back-end  : Internal Web ALB HTTPS/443
  #
  # NOTE:
  # proxy_ssl_verify is OFF to preserve the
  # behavior of the old Python VPC-1 proxy.
  # For production, configure the backend
  # certificate chain/name and enable verify.
  ##########################################
  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              log() {
                echo "[$(date -Is)] $*"
              }

              log "Installing Nginx and OpenSSL from Internal Repo"

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
                --setopt=install_weak_deps=False install -y nginx openssl

              log "Creating TLS certificate for VPC-1 listener"
              install -d -m 0750 /etc/nginx/tls

              openssl req -x509 \
                -nodes \
                -newkey rsa:3072 \
                -sha256 \
                -keyout /etc/nginx/tls/server.key \
                -out /etc/nginx/tls/server.crt \
                -days 365 \
                -subj "/CN=ec2-peter-vpc1-reverse-proxy-1a"

              chmod 0600 /etc/nginx/tls/server.key
              chmod 0644 /etc/nginx/tls/server.crt

              log "Writing Nginx reverse proxy configuration"
              cat > /etc/nginx/conf.d/peter-reverse-proxy.conf <<'NGINX'
              server {
                  listen 443 ssl;
                  server_name _;

                  server_tokens off;

                  ssl_certificate     /etc/nginx/tls/server.crt;
                  ssl_certificate_key /etc/nginx/tls/server.key;
                  ssl_protocols       TLSv1.2 TLSv1.3;
                  ssl_session_cache   shared:SSL:10m;
                  ssl_session_timeout 10m;

                  access_log /var/log/nginx/peter-reverse-proxy-access.log;
                  error_log  /var/log/nginx/peter-reverse-proxy-error.log warn;

                  location = /health {
                      access_log off;
                      add_header Content-Type text/plain;
                      return 200 'OK';
                  }

                  location / {
                      proxy_pass https://${aws_lb.web.dns_name};

                      proxy_http_version 1.1;
                      proxy_set_header Host ${aws_lb.web.dns_name};
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto https;
                      proxy_set_header Connection "";

                      proxy_connect_timeout 10s;
                      proxy_send_timeout    60s;
                      proxy_read_timeout    60s;

                      proxy_ssl_server_name on;
                      proxy_ssl_name ${aws_lb.web.dns_name};

                      # VPC-1 compatibility with the previous Python proxy.
                      # Production hardening: trust the backend CA and set this to on.
                      proxy_ssl_verify off;
                  }
              }
              NGINX

              # Remove the default server configuration if present.
              rm -f /etc/nginx/conf.d/default.conf

              # RHEL SELinux: allow Nginx to initiate connections to the backend ALB.
              if command -v setsebool >/dev/null 2>&1; then
                setsebool -P httpd_can_network_connect 1 || true
              fi

              # Open local firewall only when firewalld is active.
              if systemctl is-active --quiet firewalld; then
                firewall-cmd --permanent --add-service=https
                firewall-cmd --reload
              fi

              log "Validating Nginx configuration"
              nginx -t

              log "Enabling and starting Nginx"
              systemctl enable nginx
              systemctl restart nginx

              log "Nginx reverse proxy bootstrap completed"
              EOF

  tags = {
    Name = "ec2-peter-vpc1-reverse-proxy-1a"
    Tier = "ReverseProxy"
  }
}

############################################
# Outputs
############################################
output "reverse_proxy_instance_id" {
  description = "Peter VPC-1 reverse proxy EC2 instance ID"
  value       = aws_instance.reverse_proxy.id
}

output "reverse_proxy_private_ip" {
  description = "Peter VPC-1 reverse proxy private IP address"
  value       = aws_instance.reverse_proxy.private_ip
}

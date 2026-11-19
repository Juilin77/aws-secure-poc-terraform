############################################
# Peter VPC-1 - APP Tier
############################################


############################################
# App Tier Security Group
############################################

resource "aws_security_group" "app" {
  name        = "peter-vpc1-ec2-app-01-sg"
  description = "Security group for Peter VPC-1 App tier"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # Internal ALB-App -> App Tier
  ##########################################

  ingress {
    description     = "Allow HTTPS from internal App ALB only"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_app.id]
  }

  ##########################################
  # EICE -> App SSH
  ##########################################

  ingress {
    description     = "Allow SSH from EC2 Instance Connect Endpoint only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  ##########################################
  # App -> Internal Repository
  ##########################################

  egress {
    description = "Allow HTTPS to internal repository in AZ-B"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [
      var.repo_subnet_a_cidr,
      var.repo_subnet_b_cidr
    ]
  }

  ##########################################
  # App -> RDS
  ##########################################

  egress {
    description = "Allow MySQL to DB tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_a_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # App -> Forward Proxy
  ##########################################

  egress {
    description = "Allow Forward Proxy access"
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = [
      var.forward_proxy_subnet_a_cidr,
      var.forward_proxy_subnet_b_cidr
    ]
  }

  tags = {
    Name = "sg-peter-vpc1-ec2-app-01"
  }
}

resource "aws_instance" "app" {
  ami                         = var.app_ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = false

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              log() {
                echo "[$(date -Is)] $*"
              }

              mkdir -p /opt/poc-web
              mkdir -p /etc/poc-web/tls

              cat > /opt/poc-web/index.html <<'HTML'
              <html>
              <body>
                <h1>Peter AWS VPC-1</h1>
                <p>Private EC2 behind Application Load Balancer</p>
              </body>
              </html>
              HTML

              openssl req -x509 -nodes -newkey rsa:2048 \
                -keyout /etc/poc-web/tls/server.key \
                -out /etc/poc-web/tls/server.crt \
                -days 365 \
                -subj "/CN=ec2-peter-vpc1-app-1a"

              chmod 600 /etc/poc-web/tls/server.key

              cat > /opt/poc-web/https_server.py <<'PY'
              import http.server
              import ssl
              import functools

              class AppHandler(http.server.SimpleHTTPRequestHandler):

                  def end_headers(self):
                      self.send_header(
                          "X-Peter-App-Tier",
                          "ec2-peter-vpc1-app-1a"
                      )
                      super().end_headers()


              handler = functools.partial(
                  AppHandler,
                  directory="/opt/poc-web"
              )

              httpd = http.server.HTTPServer(
                  ("0.0.0.0", 443),
                  handler
              )

              context = ssl.SSLContext(
                  ssl.PROTOCOL_TLS_SERVER
              )

              context.load_cert_chain(
                  certfile="/etc/poc-web/tls/server.crt",
                  keyfile="/etc/poc-web/tls/server.key"
              )

              httpd.socket = context.wrap_socket(
                  httpd.socket,
                  server_side=True
              )

              httpd.serve_forever()
              PY

              cat > /etc/systemd/system/poc-web-https.service <<'SERVICE'
              [Unit]
              Description=Peter VPC-1 HTTPS Web Server
              After=network.target

              [Service]
              ExecStart=/usr/bin/python3 /opt/poc-web/https_server.py
              Restart=always
              RestartSec=5

              [Install]
              WantedBy=multi-user.target
              SERVICE

              ################################
              # Forward Proxy
              ################################

              PROXY_HOST="${aws_lb.forward_proxy.dns_name}"
              PROXY_URL="http://$${PROXY_HOST}:3128"

              ################################
              # Persistent Forward Proxy
              ################################

              cat > /etc/profile.d/peter-proxy.sh <<EOF_PROXY
              export http_proxy="$${PROXY_URL}"
              export https_proxy="$${PROXY_URL}"
              export HTTP_PROXY="$${PROXY_URL}"
              export HTTPS_PROXY="$${PROXY_URL}"

              export no_proxy="localhost,127.0.0.1,169.254.169.254,10.10.0.0/16"
              export NO_PROXY="localhost,127.0.0.1,169.254.169.254,10.10.0.0/16"
              EOF_PROXY

              chmod 644 /etc/profile.d/peter-proxy.sh


              ################################
              # Wait for Forward Proxy
              ################################

              for i in $(seq 1 30); do
                if curl \
                  --proxy "$${PROXY_URL}" \
                  --connect-timeout 5 \
                  --silent \
                  --head \
                  https://aws.amazon.com \
                  >/dev/null 2>&1; then

                  echo "Forward Proxy is ready."
                  break
                fi

                echo "Waiting for Forward Proxy... attempt $${i}/30"
                sleep 10

                if [ "$${i}" -eq 30 ]; then
                  echo "Forward Proxy did not become ready."
                  exit 1
                fi
              done

             
              
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

              ################################
              # Install MariaDB Client
              ################################

              log "Installing MariaDB Client from Internal Repo"

              dnf --disablerepo='*' --enablerepo=peter-internal \
                --setopt=install_weak_deps=False install -y mariadb105

              log "MariaDB Client installation completed"


              ################################
              # Start App Service
              ################################

              systemctl daemon-reload
              systemctl enable --now poc-web-https

              EOF

  tags = {
    Name = "ec2-peter-vpc1-app-1a"
    Tier = "App"
  }
}


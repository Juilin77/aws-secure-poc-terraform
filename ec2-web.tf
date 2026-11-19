############################################
# Peter VPC-1 - Web Tier
############################################


############################################
# Web Tier Security Group
############################################

resource "aws_security_group" "web" {
  name        = "peter-vpc1-ec2-web-01-sg"
  description = "Security group for Peter VPC-1 web tier"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # Internal ALB-Web -> Web Tier
  ##########################################

  ingress {
    description     = "Allow HTTPS from internal Web ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_web.id]
  }

  ##########################################
  # EICE -> Web SSH
  ##########################################

  ingress {
    description     = "Allow SSH from EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  ##########################################
  # Web -> App Tier
  ##########################################

  egress {
    description = "Allow HTTPS to internal App ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_a_cidr,
      var.private_subnet_b_cidr
    ]
  }

  egress {
    description = "Allow HTTPS to internal repository"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [
      var.repo_subnet_a_cidr,
      var.repo_subnet_b_cidr
    ]
  }

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
    Name = "sg-peter-vpc1-ec2-web-01"
  }
}


############################################
# Web EC2
############################################

resource "aws_instance" "web" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.web.id
  ]

  associate_public_ip_address = false

  # Recreate Web EC2 if backend configuration changes.
  user_data_replace_on_change = true


  ##########################################
  # IMDSv2
  ##########################################

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }


  ##########################################
  # Encrypted Root Volume
  ##########################################

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }


  ##########################################
  # Web Tier Service
  #
  # HTTPS frontend
  # Proxies requests to App EC2 HTTPS/443
  ##########################################

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              log() {
                echo "[$(date -Is)] $*"
              }

              mkdir -p /opt/peter-web
              mkdir -p /etc/peter-web/tls


              
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
              # Self-Signed Certificate
              # VPC-1 only
              ################################

              openssl req -x509 \
                -nodes \
                -newkey rsa:2048 \
                -keyout /etc/peter-web/tls/server.key \
                -out /etc/peter-web/tls/server.crt \
                -days 365 \
                -subj "/CN=ec2-peter-vpc1-web-1a"

              chmod 600 /etc/peter-web/tls/server.key


              ################################
              # Web Tier Python Service
              ################################

              cat > /opt/peter-web/web.py <<'PY'
              import http.server
              import http.client
              import ssl

              BACKEND_HOST = "${aws_lb.app.dns_name}"
              BACKEND_PORT = 443


              class WebTierHandler(http.server.BaseHTTPRequestHandler):

                  def proxy_request(self):

                      backend_context = ssl._create_unverified_context()

                      connection = http.client.HTTPSConnection(
                          BACKEND_HOST,
                          BACKEND_PORT,
                          context=backend_context,
                          timeout=30
                      )

                      body = None

                      if "Content-Length" in self.headers:
                          length = int(self.headers["Content-Length"])
                          body = self.rfile.read(length)

                      headers = {
                          key: value
                          for key, value in self.headers.items()
                          if key.lower() not in [
                              "host",
                              "connection",
                              "content-length"
                          ]
                      }

                      headers["Host"] = BACKEND_HOST
                      headers["X-Forwarded-For"] = self.client_address[0]
                      headers["X-Forwarded-Proto"] = "https"
                      headers["X-Web-Tier"] = "ec2-peter-vpc1-web-1a"

                      connection.request(
                          self.command,
                          self.path,
                          body=body,
                          headers=headers
                      )

                      response = connection.getresponse()

                      self.send_response(response.status)

                      # Useful for VPC-1 verification
                      self.send_header(
                          "X-Peter-Web-Tier",
                          "ec2-peter-vpc1-web-1a"
                      )

                      for key, value in response.getheaders():

                          if key.lower() not in [
                              "connection",
                              "transfer-encoding"
                          ]:
                              self.send_header(key, value)

                      self.end_headers()

                      if self.command != "HEAD":
                          self.wfile.write(response.read())

                      connection.close()


                  def do_GET(self):
                      self.proxy_request()


                  def do_HEAD(self):
                      self.proxy_request()


                  def do_POST(self):
                      self.proxy_request()


              server = http.server.ThreadingHTTPServer(
                  ("0.0.0.0", 443),
                  WebTierHandler
              )

              context = ssl.SSLContext(
                  ssl.PROTOCOL_TLS_SERVER
              )

              context.load_cert_chain(
                  certfile="/etc/peter-web/tls/server.crt",
                  keyfile="/etc/peter-web/tls/server.key"
              )

              server.socket = context.wrap_socket(
                  server.socket,
                  server_side=True
              )

              server.serve_forever()
              PY


              ################################
              # systemd Service
              ################################

              cat > /etc/systemd/system/peter-web.service <<'SERVICE'
              [Unit]
              Description=Peter VPC-1 Web Tier
              After=network.target

              [Service]
              Type=simple
              ExecStart=/usr/bin/python3 /opt/peter-web/web.py
              Restart=always
              RestartSec=5

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable --now peter-web
              EOF


  tags = {
    Name = "ec2-peter-vpc1-web-1a"
    Tier = "Web"
  }
}


############################################
# Outputs
############################################

output "web_instance_id" {
  description = "Web Tier EC2 instance ID"
  value       = aws_instance.web.id
}

output "web_private_ip" {
  description = "Web Tier private IP"
  value       = aws_instance.web.private_ip
}

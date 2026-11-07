############################################
# Peter POC - APP Tier
############################################


############################################
# App Tier Security Group
############################################

resource "aws_security_group" "app" {
  name        = "peter-poc-app-sg"
  description = "Security group for Peter POC App tier"
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
    description = "Allow HTTPS to internal repository"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
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
      var.private_subnet_cidr,
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
    cidr_blocks = [var.forward_proxy_subnet_a_cidr]
  }

  tags = {
    Name = "peter-poc-app-sg"
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
              set -e

              mkdir -p /opt/poc-web
              mkdir -p /etc/poc-web/tls

              cat > /opt/poc-web/index.html <<'HTML'
              <html>
              <body>
                <h1>Peter AWS POC</h1>
                <p>Private EC2 behind Application Load Balancer</p>
              </body>
              </html>
              HTML

              openssl req -x509 -nodes -newkey rsa:2048 \
                -keyout /etc/poc-web/tls/server.key \
                -out /etc/poc-web/tls/server.crt \
                -days 365 \
                -subj "/CN=peter-poc-app-01"

              chmod 600 /etc/poc-web/tls/server.key

              cat > /opt/poc-web/https_server.py <<'PY'
              import http.server
              import ssl
              import functools

              class AppHandler(http.server.SimpleHTTPRequestHandler):

                  def end_headers(self):
                      self.send_header(
                          "X-Peter-App-Tier",
                          "peter-poc-app-01"
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
              Description=Peter POC HTTPS Web Server
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

              PROXY_IP="${aws_instance.forward_proxy.private_ip}"
              PROXY_URL="http://$${PROXY_IP}:3128"


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
              # Install MariaDB Client
              ################################

              dnf install -y \
                --setopt=proxy="$${PROXY_URL}" \
                mariadb105
                


              ################################
              # Internal DNF Repository
              ################################

              REPO_IP="${aws_instance.repo.private_ip}"

              cat > /etc/yum.repos.d/peter-poc.repo <<EOF_REPO
              [peter-poc]
              name=Peter POC Internal Repository
              baseurl=https://$${REPO_IP}/packages/
              enabled=1
              gpgcheck=0
              sslverify=0
              EOF_REPO


              ################################
              # Start App Service
              ################################

              systemctl daemon-reload
              systemctl enable --now poc-web-https

              EOF

  tags = {
    Name = "peter-poc-app-01"
    Tier = "App"
  }
}

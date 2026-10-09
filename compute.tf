resource "aws_instance" "app" {
  ami                         = var.app_ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_a.id
  vpc_security_group_ids      = [aws_security_group.ec2_private.id]
  associate_public_ip_address = false

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

              handler = functools.partial(
                  http.server.SimpleHTTPRequestHandler,
                  directory="/opt/poc-web"
              )

              httpd = http.server.HTTPServer(
                  ("0.0.0.0", 443),
                  handler
              )

              context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
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

              systemctl daemon-reload
              systemctl enable --now poc-web-https
              EOF

  tags = {
    Name = "peter-poc-app-01"
  }
}

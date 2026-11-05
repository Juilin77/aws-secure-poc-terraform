############################################
# Peter POC - Reverse Proxy
############################################


############################################
# Reverse Proxy Security Group
############################################

resource "aws_security_group" "reverse_proxy" {
  name        = "peter-poc-reverse-proxy-sg"
  description = "Security group for Peter POC reverse proxy"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # ALB -> Reverse Proxy HTTPS
  ##########################################

  ingress {
    description     = "Allow HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ##########################################
  # EICE -> Reverse Proxy SSH
  ##########################################

  ingress {
    description     = "Allow SSH from EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  ##########################################
  # Reverse Proxy -> Internal Web ALB
  #
  # Internal ALB spans Private Subnet A/B.
  # CIDRs are used to avoid SG circular
  # dependencies in inline SG rules.
  ##########################################

  egress {
    description = "Allow HTTPS to internal Web ALB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  tags = {
    Name = "peter-poc-reverse-proxy-sg"
  }
}


############################################
# Reverse Proxy EC2
############################################

resource "aws_instance" "reverse_proxy" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.reverse_proxy.id
  ]

  associate_public_ip_address = false

  user_data_replace_on_change = true


  ##########################################
  # Require IMDSv2
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
  # Reverse Proxy
  #
  # Python standard library is used because
  # this private subnet currently has no NAT.
  #
  # Front-end : HTTPS 443
  # Back-end  : Internal ALB-Web HTTPS 443
  ##########################################

  user_data = <<-EOF
              #!/bin/bash
              set -e

              mkdir -p /opt/peter-reverse-proxy
              mkdir -p /etc/peter-reverse-proxy/tls


              ################################
              # TLS Certificate - POC only
              ################################

              openssl req -x509 \
                -nodes \
                -newkey rsa:2048 \
                -keyout /etc/peter-reverse-proxy/tls/server.key \
                -out /etc/peter-reverse-proxy/tls/server.crt \
                -days 365 \
                -subj "/CN=peter-poc-reverse-proxy-01"

              chmod 600 /etc/peter-reverse-proxy/tls/server.key


              ################################
              # Python HTTPS Reverse Proxy
              ################################

              cat > /opt/peter-reverse-proxy/reverse_proxy.py <<'PY'
              import http.server
              import http.client
              import ssl

              BACKEND_HOST = "${aws_lb.web.dns_name}"
              BACKEND_PORT = 443


              class ReverseProxyHandler(http.server.BaseHTTPRequestHandler):

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

                      connection.request(
                          self.command,
                          self.path,
                          body=body,
                          headers=headers
                      )

                      response = connection.getresponse()

                      self.send_response(response.status)

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


                  def do_PUT(self):
                      self.proxy_request()


                  def do_DELETE(self):
                      self.proxy_request()


              server = http.server.ThreadingHTTPServer(
                  ("0.0.0.0", 443),
                  ReverseProxyHandler
              )

              frontend_context = ssl.SSLContext(
                  ssl.PROTOCOL_TLS_SERVER
              )

              frontend_context.load_cert_chain(
                  certfile="/etc/peter-reverse-proxy/tls/server.crt",
                  keyfile="/etc/peter-reverse-proxy/tls/server.key"
              )

              server.socket = frontend_context.wrap_socket(
                  server.socket,
                  server_side=True
              )

              server.serve_forever()
              PY


              ################################
              # systemd Service
              ################################

              cat > /etc/systemd/system/peter-reverse-proxy.service <<'SERVICE'
              [Unit]
              Description=Peter POC Reverse Proxy
              After=network.target

              [Service]
              Type=simple
              ExecStart=/usr/bin/python3 /opt/peter-reverse-proxy/reverse_proxy.py
              Restart=always
              RestartSec=5

              [Install]
              WantedBy=multi-user.target
              SERVICE


              systemctl daemon-reload
              systemctl enable --now peter-reverse-proxy
              EOF


  tags = {
    Name = "peter-poc-reverse-proxy-01"
    Tier = "ReverseProxy"
  }
}


############################################
# Outputs
############################################

output "reverse_proxy_instance_id" {
  description = "Reverse proxy EC2 instance ID"
  value       = aws_instance.reverse_proxy.id
}

output "reverse_proxy_private_ip" {
  description = "Reverse proxy private IP address"
  value       = aws_instance.reverse_proxy.private_ip
}
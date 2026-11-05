############################################
# Peter POC - Forward Proxy
#
# Phase 1:
# - Dedicated Forward Proxy subnet
# - Forward Proxy EC2
# - Explicit proxy TCP/3128
# - No Internet route yet
############################################


############################################
# Forward Proxy Subnet
############################################

resource "aws_subnet" "forward_proxy_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.forward_proxy_subnet_a_cidr
  availability_zone       = var.availability_zone_a
  map_public_ip_on_launch = false

  tags = {
    Name = "peter-poc-forward-proxy-subnet-a"
    Tier = "EgressProxy"
  }
}


############################################
# Forward Proxy Route Table
#
# Phase 1:
# Local VPC routing only.
#
# Default route through Network Firewall
# will be added in Phase 2.
############################################

resource "aws_route_table" "forward_proxy_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "peter-poc-forward-proxy-rt-a"
  }
}

resource "aws_route_table_association" "forward_proxy_a" {
  subnet_id      = aws_subnet.forward_proxy_a.id
  route_table_id = aws_route_table.forward_proxy_a.id
}


############################################
# Forward Proxy Security Group
############################################

resource "aws_security_group" "forward_proxy" {
  name        = "peter-poc-forward-proxy-sg"
  description = "Security group for Peter POC forward proxy"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # App Tier -> Forward Proxy
  ##########################################

  ingress {
    description     = "Allow proxy access from App Tier"
    from_port       = 3128
    to_port         = 3128
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ##########################################
  # Web Tier -> Forward Proxy
  ##########################################

  ingress {
    description     = "Allow proxy access from Web Tier"
    from_port       = 3128
    to_port         = 3128
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  ##########################################
  # Repo Server -> Forward Proxy
  ##########################################

  ingress {
    description     = "Allow proxy access from Repository Server"
    from_port       = 3128
    to_port         = 3128
    protocol        = "tcp"
    security_groups = [aws_security_group.repo.id]
  }

  ##########################################
  # EICE -> SSH
  ##########################################

  ingress {
    description     = "Allow SSH from EICE"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  ##########################################
  # Proxy Internet Egress
  #
  # Routing is NOT enabled yet.
  # Phase 2 will send this through NFW + NAT.
  ##########################################

  egress {
    description = "Allow HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "peter-poc-forward-proxy-sg"
  }
}


############################################
# Forward Proxy EC2
############################################

resource "aws_instance" "forward_proxy" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.forward_proxy_a.id

  vpc_security_group_ids = [
    aws_security_group.forward_proxy.id
  ]

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


  ##########################################
  # Minimal Explicit Forward Proxy
  #
  # Phase 1 validation only.
  # Squid will replace this after
  # Internet egress routing is available.
  ##########################################

  user_data = <<-EOF
              #!/bin/bash
              set -e

              mkdir -p /opt/peter-forward-proxy

              cat > /opt/peter-forward-proxy/proxy.py <<'PY'
              import select
              import socket
              import socketserver


              class ProxyHandler(socketserver.StreamRequestHandler):

                  def handle(self):

                      request_line = self.rfile.readline().decode(
                          "iso-8859-1"
                      ).strip()

                      if not request_line:
                          return

                      parts = request_line.split()

                      if len(parts) < 3:
                          return

                      method, target, version = parts

                      headers = {}

                      while True:
                          line = self.rfile.readline().decode(
                              "iso-8859-1"
                          )

                          if line in ("\r\n", "\n", ""):
                              break

                          key, value = line.split(":", 1)
                          headers[key.strip()] = value.strip()


                      ################################
                      # HTTPS CONNECT
                      ################################

                      if method.upper() == "CONNECT":

                          host, port = target.rsplit(":", 1)

                          remote = socket.create_connection(
                              (host, int(port)),
                              timeout=30
                          )

                          self.wfile.write(
                              b"HTTP/1.1 200 Connection Established\r\n\r\n"
                          )

                          sockets = [
                              self.connection,
                              remote
                          ]

                          while True:

                              readable, _, _ = select.select(
                                  sockets,
                                  [],
                                  [],
                                  60
                              )

                              if not readable:
                                  break

                              for sock in readable:

                                  data = sock.recv(65536)

                                  if not data:
                                      remote.close()
                                      return

                                  if sock is self.connection:
                                      remote.sendall(data)
                                  else:
                                      self.connection.sendall(data)

                          remote.close()
                          return


                      ################################
                      # HTTP Proxy
                      ################################

                      host_header = headers.get("Host")

                      if not host_header:
                          return

                      if ":" in host_header:
                          host, port = host_header.rsplit(":", 1)
                          port = int(port)
                      else:
                          host = host_header
                          port = 80

                      remote = socket.create_connection(
                          (host, port),
                          timeout=30
                      )

                      path = target

                      if target.startswith("http://"):
                          remainder = target[7:]
                          slash = remainder.find("/")
                          path = (
                              remainder[slash:]
                              if slash >= 0
                              else "/"
                          )

                      request = (
                          f"{method} {path} {version}\r\n"
                      )

                      remote.sendall(
                          request.encode("iso-8859-1")
                      )

                      for key, value in headers.items():

                          if key.lower() in [
                              "proxy-connection",
                              "connection"
                          ]:
                              continue

                          remote.sendall(
                              f"{key}: {value}\r\n".encode(
                                  "iso-8859-1"
                              )
                          )

                      remote.sendall(
                          b"Connection: close\r\n\r\n"
                      )

                      while True:

                          data = remote.recv(65536)

                          if not data:
                              break

                          self.connection.sendall(data)

                      remote.close()


              class ThreadingProxy(
                  socketserver.ThreadingMixIn,
                  socketserver.TCPServer
              ):

                  allow_reuse_address = True
                  daemon_threads = True


              with ThreadingProxy(
                  ("0.0.0.0", 3128),
                  ProxyHandler
              ) as server:

                  server.serve_forever()
              PY


              ################################
              # systemd
              ################################

              cat > /etc/systemd/system/peter-forward-proxy.service <<'SERVICE'
              [Unit]
              Description=Peter POC Forward Proxy
              After=network.target

              [Service]
              Type=simple
              ExecStart=/usr/bin/python3 /opt/peter-forward-proxy/proxy.py
              Restart=always
              RestartSec=5

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable --now peter-forward-proxy
              EOF


  tags = {
    Name = "peter-poc-forward-proxy-01"
    Tier = "ForwardProxy"
  }
}


############################################
# Outputs
############################################

output "forward_proxy_instance_id" {
  value = aws_instance.forward_proxy.id
}

output "forward_proxy_private_ip" {
  value = aws_instance.forward_proxy.private_ip
}

output "forward_proxy_port" {
  value = 3128
}

############################################
# Forward Proxy -> NAT Instance
############################################

resource "aws_route" "forward_proxy_internet" {
  route_table_id         = aws_route_table.forward_proxy_a.id
  destination_cidr_block = "0.0.0.0/0"

  network_interface_id = aws_instance.nat.primary_network_interface_id
}
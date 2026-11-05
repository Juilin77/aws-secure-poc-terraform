############################################
# Peter POC - Internal Repository Server
#
# Phase 1:
# - Private EC2
# - No public IP
# - HTTPS repository endpoint
# - SSH management through EICE only
# - No outbound Internet access
############################################


############################################
# Repository Security Group
############################################

resource "aws_security_group" "repo" {
  name        = "peter-poc-repo-sg"
  description = "Security group for Peter POC internal repository server"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # Application EC2 -> Repository HTTPS
  ##########################################

  ingress {
    description     = "Allow HTTPS from application EC2"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ##########################################
  # EICE -> Repository SSH
  ##########################################

  ingress {
    description     = "Allow SSH from EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  ##########################################
  # Repository -> Forward Proxy
  ##########################################

  egress {
    description = "Allow Forward Proxy access"
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = [var.forward_proxy_subnet_a_cidr]
  }

  tags = {
    Name = "peter-poc-repo-sg"
  }
}


############################################
# Repository EC2
############################################

resource "aws_instance" "repo" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.repo.id
  ]

  associate_public_ip_address = false


  ##########################################
  # Require IMDSv2
  ##########################################

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }


  ##########################################
  # Encrypted Root Disk
  ##########################################

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 10
  }

  ##########################################
  # Repository Web Service
  #
  # Repo server uses the Forward Proxy for
  # controlled Internet access to download
  # packages and repository tooling.
  ##########################################

  user_data = <<-EOF
            #!/bin/bash
            set -euxo pipefail

            ################################
            # Variables
            ################################

            PROXY_IP="${aws_instance.forward_proxy.private_ip}"
            PROXY_URL="http://$${PROXY_IP}:3128"

            REPO_ROOT="/opt/peter-repo"
            PACKAGE_DIR="$${REPO_ROOT}/packages"


            ################################
            # Repository Directories
            ################################

            mkdir -p "$${PACKAGE_DIR}"
            mkdir -p /etc/peter-repo/tls


            ################################
            # Repository Landing Page
            ################################

            cat > "$${REPO_ROOT}/index.html" <<'HTML'
            <html>
            <head>
              <title>Peter POC Repository</title>
            </head>
            <body>
              <h1>Peter POC Internal Repository</h1>
              <p>Internal package repository server.</p>
              <p>Repository path: /packages/</p>
            </body>
            </html>
            HTML


            ################################
            # Repository README
            ################################

            cat > "$${PACKAGE_DIR}/README.txt" <<'TXT'
            Peter POC Internal Repository

            Repository contents are automatically
            prepared during EC2 bootstrap.

            POC validates:
            - Private repository server
            - HTTPS access
            - Forward Proxy controlled egress
            - Security Group segmentation
            - DNF/YUM repository metadata
            - Internal EC2 package installation
            TXT


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
            # Install Repository Tools
            ################################

            dnf install -y \
              --setopt=proxy="$${PROXY_URL}" \
              createrepo_c \
              dnf-plugins-core


            ################################
            # Download POC RPM
            ################################

            dnf download \
              --setopt=proxy="$${PROXY_URL}" \
              --destdir "$${PACKAGE_DIR}" \
              tree


            ################################
            # Generate Repository Metadata
            ################################

            createrepo_c "$${PACKAGE_DIR}"


            ################################
            # Self-Signed TLS Certificate
            #
            # POC only.
            ################################

            openssl req -x509 \
              -nodes \
              -newkey rsa:2048 \
              -keyout /etc/peter-repo/tls/server.key \
              -out /etc/peter-repo/tls/server.crt \
              -days 365 \
              -subj "/CN=peter-poc-repo-01"

            chmod 600 /etc/peter-repo/tls/server.key


            ################################
            # HTTPS Python Repository Server
            ################################

            cat > "$${REPO_ROOT}/repo_server.py" <<'PY'
            import http.server
            import ssl
            import functools

            handler = functools.partial(
                http.server.SimpleHTTPRequestHandler,
                directory="/opt/peter-repo"
            )

            httpd = http.server.HTTPServer(
                ("0.0.0.0", 443),
                handler
            )

            context = ssl.SSLContext(
                ssl.PROTOCOL_TLS_SERVER
            )

            context.load_cert_chain(
                certfile="/etc/peter-repo/tls/server.crt",
                keyfile="/etc/peter-repo/tls/server.key"
            )

            httpd.socket = context.wrap_socket(
                httpd.socket,
                server_side=True
            )

            httpd.serve_forever()
            PY


            ################################
            # systemd Service
            ################################

            cat > /etc/systemd/system/peter-repo.service <<'SERVICE'
            [Unit]
            Description=Peter POC Internal Repository Server
            After=network-online.target
            Wants=network-online.target

            [Service]
            Type=simple
            ExecStart=/usr/bin/python3 /opt/peter-repo/repo_server.py
            Restart=always
            RestartSec=5

            [Install]
            WantedBy=multi-user.target
            SERVICE


            ################################
            # Start Repository Service
            ################################

            systemctl daemon-reload
            systemctl enable --now peter-repo


            ################################
            # Bootstrap Validation
            ################################

            test -f "$${PACKAGE_DIR}/repodata/repomd.xml"

            find "$${PACKAGE_DIR}" \
              -maxdepth 2 \
              -type f \
              | sort

            curl \
              --noproxy "*" \
              -k \
              --fail \
              https://127.0.0.1/packages/repodata/repomd.xml \
              >/dev/null

            echo "Peter POC Repository bootstrap completed successfully."

            EOF


  tags = {
    Name = "peter-poc-repo-01"
    Tier = "Repository"
  }
}


############################################
# Outputs
############################################

output "repo_instance_id" {
  description = "Peter POC repository EC2 instance ID"
  value       = aws_instance.repo.id
}

output "repo_private_ip" {
  description = "Peter POC repository private IP address"
  value       = aws_instance.repo.private_ip
}

output "repo_https_url" {
  description = "Peter POC internal repository HTTPS URL"
  value       = "https://${aws_instance.repo.private_ip}"
}
############################################
# Peter VPC-1 - Internal Repository Server
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
  name        = "peter-vpc1-ec2-repo-01-sg"
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

  # Web EC2 -> Internal Repo HTTPS
  ingress {
    description     = "Allow HTTPS from Web EC2"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  # Forward Proxy -> Internal Repo HTTPS
  ingress {
    description     = "Allow HTTPS from Forward Proxy"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.forward_proxy.id]
  }

  # Reverse Proxy -> Internal Repo HTTPS
  ingress {
    description     = "Allow HTTPS from Reverse Proxy"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.reverse_proxy.id]
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
    cidr_blocks = [
      var.forward_proxy_subnet_a_cidr,
      var.forward_proxy_subnet_b_cidr
    ]
  }

  ##########################################
  # Repository -> Internet via NAT-A
  ##########################################

  egress {
    description = "Allow HTTPS to AL2023 repository via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-peter-vpc1-ec2-repo-01"
  }

}


############################################
# Repository EC2
############################################

resource "aws_instance" "repo" {
  ami           = var.app_ami_id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.repo_b.id

  vpc_security_group_ids = [
    aws_security_group.repo.id
  ]

  associate_public_ip_address = false


  depends_on = [
    aws_instance.nat,
    aws_route.repo_b_to_nat_a,
    aws_eip_association.nat,
  ]


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
            set -euo pipefail

            log() {
              echo "[$(date -Is)] $*"
            }

            ################################
            # Variables
            ################################


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
            # Wait for AL2023 Repository
            ################################

            DNF_READY=false

            for i in $(seq 1 40); do
              if dnf makecache --refresh -q >/dev/null 2>&1; then
                DNF_READY=true
                break
              fi

              log "Waiting for AL2023 Repository ($${i}/40)"
              sleep 15
            done

            if [ "$DNF_READY" != "true" ]; then
              log "ERROR: AL2023 Repository unavailable"
              exit 1
            fi


            ################################
            # Install Repository Tools
            ################################

            dnf install -y \
              createrepo_c \
              dnf-plugins-core


            ################################
            # Download POC RPM
            ################################

            dnf download \
              --resolve \
              --alldeps \
              --destdir "$${PACKAGE_DIR}" \
              squid \
              nginx \
              openssl \
              tree \
              mariadb105


            ################################
            # Generate Repository Metadata
            ################################

            createrepo_c "$${PACKAGE_DIR}"


            ################################
            # Install fixed Repository TLS certificate
            ################################

            cat > /etc/peter-repo/tls/server.crt <<'CERT'
            ${file("${path.module}/repo-server.crt")}
            CERT

            cat > /etc/peter-repo/tls/server.key <<'KEY'
            ${file("${path.module}/repo-server.key")}
            KEY

            chmod 0644 /etc/peter-repo/tls/server.crt
            chmod 0600 /etc/peter-repo/tls/server.key


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

            
            REPO_READY=false

            for i in $(seq 1 30); do
              if curl --noproxy '*' \
                --fail --silent \
                --resolve repo.vpc1.internal:443:127.0.0.1 \
                --cacert /etc/peter-repo/tls/server.crt \
                --connect-timeout 2 \
                --max-time 5 \
                https://repo.vpc1.internal/packages/repodata/repomd.xml \
                -o /dev/null; then
                REPO_READY=true
                break
              fi

              log "Waiting for local Repository ($${i}/30)"
              sleep 2
            done

            if [ "$${REPO_READY}" != "true" ]; then
              log "ERROR: Local Repository HTTPS service not ready"
              exit 1
            fi


            echo "Peter POC Repository bootstrap completed successfully."

            EOF


  tags = {
    Name = "ec2-peter-vpc1-repo-1b"
    Tier = "Repository"
  }
}


############################################
# Outputs
############################################

output "repo_instance_id" {
  description = "Peter VPC-1 repository EC2 instance ID"
  value       = aws_instance.repo.id
}

output "repo_private_ip" {
  description = "Peter VPC-1 repository private IP address"
  value       = aws_instance.repo.private_ip
}

output "repo_https_url" {
  description = "Peter VPC-1 internal repository HTTPS URL"
  value       = "https://${aws_instance.repo.private_ip}"
}

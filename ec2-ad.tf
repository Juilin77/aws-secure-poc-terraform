############################################
# Peter POC - Active Directory Tier
############################################


############################################
# Latest Windows Server 2022 AMI
############################################

data "aws_ssm_parameter" "windows_server_2022_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}


############################################
# AD Security Group
############################################

resource "aws_security_group" "ad" {
  name        = "peter-poc-ad-sg"
  description = "Security group for Peter POC Active Directory"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # RDP through EICE
  ##########################################

  ingress {
    description     = "RDP from EC2 Instance Connect Endpoint"
    from_port       = 3389
    to_port         = 3389
    protocol        = "tcp"
    security_groups = [aws_security_group.eice.id]
  }

  ##########################################
  # DNS
  ##########################################

  ingress {
    description = "DNS TCP from private subnets"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ingress {
    description = "DNS UDP from private subnets"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # Kerberos
  ##########################################

  ingress {
    description = "Kerberos TCP"
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ingress {
    description = "Kerberos UDP"
    from_port   = 88
    to_port     = 88
    protocol    = "udp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # LDAP / LDAPS
  ##########################################

  ingress {
    description = "LDAP TCP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ingress {
    description = "LDAP UDP"
    from_port   = 389
    to_port     = 389
    protocol    = "udp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ingress {
    description = "LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # SMB
  ##########################################

  ingress {
    description = "SMB"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # RPC Endpoint Mapper
  ##########################################

  ingress {
    description = "RPC Endpoint Mapper"
    from_port   = 135
    to_port     = 135
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # Kerberos Password Change
  ##########################################

  ingress {
    description = "Kerberos password TCP"
    from_port   = 464
    to_port     = 464
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ingress {
    description = "Kerberos password UDP"
    from_port   = 464
    to_port     = 464
    protocol    = "udp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # Global Catalog
  ##########################################

  ingress {
    description = "Global Catalog"
    from_port   = 3268
    to_port     = 3269
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # Dynamic RPC
  ##########################################

  ingress {
    description = "Dynamic RPC"
    from_port   = 49152
    to_port     = 65535
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # Outbound
  #
  # POC initially allows VPC communication.
  # We can tighten this after AD/WSUS testing.
  ##########################################

  egress {
    description = "Allow VPC communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "peter-poc-ad-sg"
  }
}


############################################
# Active Directory EC2
############################################

resource "aws_instance" "ad" {
  ami           = data.aws_ssm_parameter.windows_server_2022_ami.value
  instance_type = "t3.medium"

  key_name = "peter-poc-ad-breakglass"

  subnet_id = aws_subnet.private_a.id

  vpc_security_group_ids = [
    aws_security_group.ad.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ad.name

  associate_public_ip_address = false

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 50
  }

  user_data = <<-EOF
              <powershell>

              $ErrorActionPreference = "Stop"

              ############################################
              # Peter POC - AD01 Bootstrap
              ############################################

              $ComputerName = "PETER-AD01"
              $DomainName   = "peterpoc.local"
              $NetBIOSName  = "PETERPOC"

              $DsrmSecretId       = "peter-poc/ad/bootstrap"
              $DomainJoinSecretId = "peter-poc/ad/domain-join"
              
              $Region = "ap-southeast-1"

              $ProxyIP   = "${aws_instance.forward_proxy.private_ip}"
              $ProxyPort = 3128

              # AmazonProvidedDNS = VPC network address + 2
              $VpcDns = "${cidrhost(var.vpc_cidr, 2)}"

              $WorkDir      = "C:\\PeterPOC"
              $CompleteFlag = "$WorkDir\\ad-complete.flag"
              $LogFile      = "$WorkDir\\ad-bootstrap.log"


              ############################################
              # Create Working Directory
              ############################################

              New-Item `
                -Path $WorkDir `
                -ItemType Directory `
                -Force |
                Out-Null


              ############################################
              # Helper Function - Logging
              ############################################

              function Write-POCLog {

                  param(
                      [string]$Message
                  )

                  $Timestamp = Get-Date `
                    -Format "yyyy-MM-dd HH:mm:ss"

                  "$Timestamp $Message" |
                    Out-File `
                      -FilePath $LogFile `
                      -Append `
                      -Encoding utf8
              }


              ############################################
              # Helper Function - Wait for Forward Proxy
              ############################################

              function Wait-POCForwardProxy {

                  for ($i = 1; $i -le 30; $i++) {

                      $ProxyReady = Test-NetConnection `
                        -ComputerName $ProxyIP `
                        -Port $ProxyPort `
                        -InformationLevel Quiet

                      if ($ProxyReady) {

                          Write-POCLog `
                            "Forward Proxy is reachable."

                          return
                      }

                      Write-POCLog `
                        "Waiting for Forward Proxy. Attempt $i/30."

                      Start-Sleep `
                        -Seconds 10
                  }

                  throw "Forward Proxy is not reachable."
              }


              ############################################
              # Helper Function - Configure AWS Proxy
              ############################################

              function Set-POCAWSProxy {

                  Write-POCLog `
                    "Configuring AWS PowerShell proxy."

                  Set-AWSProxy `
                    -Hostname $ProxyIP `
                    -Port $ProxyPort `
                    -BypassList @(
                      "169.254.169.254",
                      "127.0.0.1",
                      "localhost"
                    )
              }


              ############################################
              # Start Bootstrap
              ############################################

              Write-POCLog `
                "AD bootstrap started."


              ############################################
              # Configure Break-glass Local Administrator
              ############################################

              Write-POCLog `
                "Configuring break-glass local Administrator credential."

              Wait-POCForwardProxy

              Set-POCAWSProxy

              ############################################
              # Already Completed
              ############################################

              if (Test-Path $CompleteFlag) {

                  Write-POCLog `
                    "AD bootstrap already completed."

                  exit 0
              }


              ############################################
              # Stage 1
              # Rename Computer
              ############################################

              if ($env:COMPUTERNAME -ne $ComputerName) {

                  Write-POCLog `
                    "Renaming computer to $ComputerName."

                  Rename-Computer `
                    -NewName $ComputerName `
                    -Force

                  Write-POCLog `
                    "Restarting after computer rename."

                  Restart-Computer `
                    -Force

                  exit 0
              }


              ############################################
              # Stage 2
              # Install AD DS + DNS
              ############################################

              $ADFeature = Get-WindowsFeature `
                AD-Domain-Services

              if (
                  $ADFeature.InstallState -ne "Installed"
              ) {

                  Write-POCLog `
                    "Installing AD DS and DNS roles."

                  $FeatureResult = Install-WindowsFeature `
                    AD-Domain-Services, `
                    DNS `
                    -IncludeManagementTools

                  if (-not $FeatureResult.Success) {

                      throw `
                        "AD DS / DNS feature installation failed."
                  }

                  Write-POCLog `
                    "AD DS and DNS roles installed."

                  if (
                      $FeatureResult.RestartNeeded -eq "Yes"
                  ) {

                      Write-POCLog `
                        "Restart required after role installation."

                      Restart-Computer `
                        -Force

                      exit 0
                  }
              }


              ############################################
              # Stage 3
              # Detect Existing Domain Controller
              ############################################

              $ComputerSystem = Get-CimInstance `
                Win32_ComputerSystem

              if (
                  $ComputerSystem.DomainRole -lt 4
              ) {

                  Write-POCLog `
                    "Server is not yet a Domain Controller."


                  ##########################################
                  # Wait for Forward Proxy
                  ##########################################

                  Wait-POCForwardProxy


                  ##########################################
                  # Configure AWS PowerShell Proxy
                  ##########################################

                  Set-POCAWSProxy


                  ##########################################
                  # Retrieve DSRM Password
                  ##########################################

                  Write-POCLog `
                    "Retrieving AD bootstrap secret."

                  $SecretResponse = Get-SECSecretValue `
                    -SecretId $DsrmSecretId `
                    -Region $Region

                  if (
                      [string]::IsNullOrWhiteSpace(
                          $SecretResponse.SecretString
                      )
                  ) {

                      throw `
                        "AD bootstrap SecretString is empty."
                  }

                  $Secret = `
                    $SecretResponse.SecretString |
                      ConvertFrom-Json

                  if (
                      [string]::IsNullOrWhiteSpace(
                          $Secret.dsrm_password
                      )
                  ) {

                      throw `
                        "dsrm_password is missing."
                  }


                  ##########################################
                  # Convert DSRM Password
                  ##########################################

                  $SafeModePassword = `
                    ConvertTo-SecureString `
                      $Secret.dsrm_password `
                      -AsPlainText `
                      -Force


                  ##########################################
                  # Create AD Forest
                  ##########################################

                  Write-POCLog `
                    "Creating AD forest $DomainName."

                  Install-ADDSForest `
                    -DomainName $DomainName `
                    -DomainNetbiosName $NetBIOSName `
                    -InstallDNS `
                    -SafeModeAdministratorPassword `
                      $SafeModePassword `
                    -NoRebootOnCompletion:$true `
                    -Force


                  ##########################################
                  # Clear DSRM Secret Variables
                  ##########################################

                  $SafeModePassword = $null
                  $Secret           = $null
                  $SecretResponse   = $null

                  Remove-Variable `
                    SafeModePassword `
                    -ErrorAction SilentlyContinue

                  Remove-Variable `
                    Secret `
                    -ErrorAction SilentlyContinue

                  Remove-Variable `
                    SecretResponse `
                    -ErrorAction SilentlyContinue


                  ##########################################
                  # Reboot after Forest Creation
                  ##########################################

                  Write-POCLog `
                    "Forest creation completed. Restarting."

                  Restart-Computer `
                    -Force

                  exit 0
              }


              ############################################
              # Stage 4
              # Post-Reboot AD Validation
              ############################################

              Write-POCLog `
                "Domain Controller detected."


              ############################################
              # Wait for AD Services
              ############################################

              $Services = @(
                  "ADWS",
                  "DNS",
                  "KDC",
                  "Netlogon"
              )

              foreach (
                  $ServiceName in $Services
              ) {

                  $Ready = $false

                  for (
                      $i = 1;
                      $i -le 30;
                      $i++
                  ) {

                      $Service = Get-Service `
                        -Name $ServiceName `
                        -ErrorAction SilentlyContinue

                      if (
                          $null -ne $Service -and
                          $Service.Status -eq "Running"
                      ) {

                          $Ready = $true
                          break
                      }

                      Write-POCLog `
                        "Waiting for service $ServiceName. Attempt $i/30."

                      Start-Sleep `
                        -Seconds 10
                  }

                  if (-not $Ready) {

                      throw `
                        "Service $ServiceName did not become ready."
                  }
              }


              ############################################
              # Configure DC DNS Client
              ############################################

              $PrimaryNIC = Get-NetIPConfiguration |
                Where-Object {
                    $null -ne $_.IPv4DefaultGateway
                } |
                Select-Object `
                  -First 1

              if (
                  $null -eq $PrimaryNIC
              ) {

                  throw `
                    "Unable to identify primary network interface."
              }

              $LocalIPv4 = `
                $PrimaryNIC.IPv4Address.IPAddress

              Write-POCLog `
                "Configuring DNS client to use local DC IP $LocalIPv4."

              Set-DnsClientServerAddress `
                -InterfaceIndex `
                  $PrimaryNIC.InterfaceIndex `
                -ServerAddresses `
                  $LocalIPv4


              ############################################
              # Configure DNS Forwarder
              ############################################

              Write-POCLog `
                "Configuring DNS forwarder to AmazonProvidedDNS $VpcDns."

              Set-DnsServerForwarder `
                -IPAddress $VpcDns


              ############################################
              # Validate Active Directory
              ############################################

              Import-Module `
                ActiveDirectory

              $Domain = Get-ADDomain `
                -Identity $DomainName `
                -ErrorAction Stop

              if (
                  $Domain.DNSRoot -ne $DomainName
              ) {

                  throw `
                    "AD domain validation failed."
              }

              Write-POCLog `
                "AD domain $DomainName validated successfully."


              ############################################
              # Wait for Forward Proxy after Reboot
              ############################################

              Wait-POCForwardProxy


              ############################################
              # Configure AWS Proxy after Reboot
              ############################################

              Set-POCAWSProxy


              ############################################
              # Retrieve Domain Join Secret
              ############################################

              Write-POCLog `
                "Retrieving domain join credential."

              $DomainJoinResponse = Get-SECSecretValue `
                -SecretId $DomainJoinSecretId `
                -Region $Region

              if (
                  [string]::IsNullOrWhiteSpace(
                      $DomainJoinResponse.SecretString
                  )
              ) {

                  throw `
                    "Domain join SecretString is empty."
              }

              $DomainJoinSecret = `
                $DomainJoinResponse.SecretString |
                  ConvertFrom-Json

              if (
                  [string]::IsNullOrWhiteSpace(
                      $DomainJoinSecret.password
                  )
              ) {

                  throw `
                    "Domain join password is missing."
              }


              ############################################
              # Convert Domain Administrator Password
              ############################################

              $DomainAdminPassword = `
                ConvertTo-SecureString `
                  $DomainJoinSecret.password `
                  -AsPlainText `
                  -Force


              ############################################
              # Reset Domain Administrator Password
              ############################################

              Write-POCLog `
                "Synchronizing Domain Administrator password."

              Set-ADAccountPassword `
                -Identity "Administrator" `
                -Reset `
                -NewPassword `
                  $DomainAdminPassword

              Enable-ADAccount `
                -Identity "Administrator"

              Write-POCLog `
                "Domain Administrator password synchronized."


              ############################################
              # Clear Domain Join Secret Variables
              ############################################

              $DomainAdminPassword = $null
              $DomainJoinSecret    = $null
              $DomainJoinResponse  = $null

              Remove-Variable `
                DomainAdminPassword `
                -ErrorAction SilentlyContinue

              Remove-Variable `
                DomainJoinSecret `
                -ErrorAction SilentlyContinue

              Remove-Variable `
                DomainJoinResponse `
                -ErrorAction SilentlyContinue


              ############################################
              # Final Validation
              ############################################

              $Administrator = Get-ADUser `
                -Identity "Administrator" `
                -Properties Enabled `
                -ErrorAction Stop

              if (
                  -not $Administrator.Enabled
              ) {

                  throw `
                    "Domain Administrator account is not enabled."
              }


              ############################################
              # Completed
              ############################################

              "AD bootstrap completed successfully." |
                Out-File `
                  -FilePath $CompleteFlag `
                  -Encoding ascii `
                  -Force

              Write-POCLog `
                "AD bootstrap completed successfully."

              </powershell>

              <persist>true</persist>

              <powershellArguments>
              -ExecutionPolicy Bypass -NoProfile -NonInteractive
              </powershellArguments>
              EOF

  tags = {
    Name = "peter-poc-ad01"
    Tier = "ActiveDirectory"
  }
}


############################################
# Outputs
############################################

output "ad_instance_id" {
  description = "Active Directory EC2 instance ID"
  value       = aws_instance.ad.id
}

output "ad_private_ip" {
  description = "Active Directory private IP"
  value       = aws_instance.ad.private_ip
}

############################################
# AD Bootstrap Secret
#
# Secret value is stored outside Terraform.
# Terraform only reads the secret ARN.
############################################

data "aws_secretsmanager_secret" "ad_bootstrap" {
  name = "peter-poc/ad/bootstrap"
}

data "aws_secretsmanager_secret" "ad_domain_join" {
  name = "peter-poc/ad/domain-join"
}

resource "aws_iam_role_policy" "ad_secret_read" {
  name = "peter-poc-ad-secret-read"
  role = aws_iam_role.ad.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadADBootstrapSecrets"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = [
          data.aws_secretsmanager_secret.ad_bootstrap.arn,
          data.aws_secretsmanager_secret.ad_domain_join.arn
        ]

      }
    ]

  })
}

############################################
# AD EC2 IAM Role
############################################

resource "aws_iam_role" "ad" {
  name = "peter-poc-ad-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  permissions_boundary = var.permissions_boundary_arn

  tags = {
    Name = "peter-poc-ad-role"
  }
}

############################################
# AD EC2 Instance Profile
############################################

resource "aws_iam_instance_profile" "ad" {
  name = "peter-poc-ad-instance-profile"
  role = aws_iam_role.ad.name
}

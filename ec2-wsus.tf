############################################
# Peter POC - WSUS Tier
############################################


############################################
# WSUS Security Group
############################################

resource "aws_security_group" "wsus" {
  name        = "peter-poc-wsus-sg"
  description = "Security group for Peter POC WSUS"
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
  # WSUS HTTP
  ##########################################

  ingress {
    description = "WSUS HTTP from private subnets"
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # WSUS HTTPS
  ##########################################

  ingress {
    description = "WSUS HTTPS from private subnets"
    from_port   = 8531
    to_port     = 8531
    protocol    = "tcp"

    cidr_blocks = [
      var.private_subnet_cidr,
      var.private_subnet_b_cidr
    ]
  }

  ##########################################
  # DNS to AD
  ##########################################

  egress {
    description = "DNS TCP to AD"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.ad.private_ip}/32"]
  }

  egress {
    description = "DNS UDP to AD"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["${aws_instance.ad.private_ip}/32"]
  }

  ##########################################
  # Forward Proxy
  ##########################################

  egress {
    description = "Allow Forward Proxy access"
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = [var.forward_proxy_subnet_a_cidr]
  }

  ##########################################
  # AD communication
  ##########################################

  egress {
    description = "Allow communication to AD"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_instance.ad.private_ip}/32"]
  }

  tags = {
    Name = "peter-poc-wsus-sg"
  }
}


############################################
# WSUS EC2
############################################

resource "aws_instance" "wsus" {
  ami           = data.aws_ssm_parameter.windows_server_2022_ami.value
  instance_type = "t3.medium"

  iam_instance_profile = aws_iam_instance_profile.wsus.name

  subnet_id = aws_subnet.private_b.id

  vpc_security_group_ids = [
    aws_security_group.wsus.id
  ]

  associate_public_ip_address = false

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 80
  }

  user_data = <<-EOF
              <powershell>

              $ErrorActionPreference = "Stop"


              ############################################
              # Peter POC - WSUS01 Bootstrap
              ############################################

              $ComputerName = "PETER-WSUS01"
              $DomainName   = "peterpoc.local"
              $AdFqdn       = "PETER-AD01.peterpoc.local"
              $AdIp         = "${aws_instance.ad.private_ip}"

              $DomainJoinSecretId = "peter-poc/ad/domain-join"
              $Region             = "ap-southeast-1"

              $ProxyIP   = "${aws_instance.forward_proxy.private_ip}"
              $ProxyPort = 3128

              $WorkDir      = "C:\\PeterPOC"
              $CompleteFlag = "$WorkDir\\wsus-complete.flag"
              $LogFile      = "$WorkDir\\wsus-bootstrap.log"

              $WsusContentDir = "C:\\WSUS"


              ############################################
              # Create Working Directory
              ############################################

              New-Item `
                -Path $WorkDir `
                -ItemType Directory `
                -Force |
                Out-Null


              ############################################
              # Helper - Logging
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
              # Helper - Wait for Forward Proxy
              ############################################

              function Wait-POCForwardProxy {

                  for ($i = 1; $i -le 30; $i++) {

                      if (
                          Test-NetConnection `
                            -ComputerName $ProxyIP `
                            -Port $ProxyPort `
                            -InformationLevel Quiet
                      ) {

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
              # Helper - Configure AWS PowerShell Proxy
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
              # Start
              ############################################

              Write-POCLog `
                "WSUS bootstrap started."


              ############################################
              # Already Complete
              ############################################

              if (Test-Path $CompleteFlag) {

                  Write-POCLog `
                    "WSUS bootstrap already completed."

                  exit 0
              }


              ############################################
              # Stage 1
              # Rename Computer
              ############################################

              if (
                  $env:COMPUTERNAME -ne $ComputerName
              ) {

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
              # Configure DNS to AD01
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

              Set-DnsClientServerAddress `
                -InterfaceIndex `
                  $PrimaryNIC.InterfaceIndex `
                -ServerAddresses `
                  $AdIp

              Write-POCLog `
                "DNS configured to AD01 $AdIp."


              ############################################
              # Wait for AD DNS
              ############################################

              $DomainReady = $false

              for ($i = 1; $i -le 60; $i++) {

                  try {

                      Resolve-DnsName `
                        -Name $DomainName `
                        -ErrorAction Stop |
                        Out-Null

                      if (
                          Test-NetConnection `
                            -ComputerName $AdFqdn `
                            -Port 389 `
                            -InformationLevel Quiet
                      ) {

                          $DomainReady = $true
                          break
                      }
                  }
                  catch {
                  }

                  Write-POCLog `
                    "Waiting for AD domain. Attempt $i/60."

                  Start-Sleep `
                    -Seconds 10
              }

              if (-not $DomainReady) {

                  throw `
                    "AD domain did not become ready."
              }


              ############################################
              # Stage 3
              # Join Domain if not already joined
              ############################################

              $ComputerSystem = Get-CimInstance `
                Win32_ComputerSystem

              if (
                  -not $ComputerSystem.PartOfDomain
              ) {

                  Wait-POCForwardProxy
                  Set-POCAWSProxy

                  Write-POCLog `
                    "Retrieving domain join credential."

                  $DomainJoinResponse = `
                    Get-SECSecretValue `
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
                          $DomainJoinSecret.username
                      ) -or
                      [string]::IsNullOrWhiteSpace(
                          $DomainJoinSecret.password
                      )
                  ) {

                      throw `
                        "Domain join username/password is missing."
                  }

                  $SecurePassword = `
                    ConvertTo-SecureString `
                      $DomainJoinSecret.password `
                      -AsPlainText `
                      -Force

                  $DomainCredential = `
                    New-Object `
                      System.Management.Automation.PSCredential `
                      (
                        $DomainJoinSecret.username,
                        $SecurePassword
                      )

                  Write-POCLog `
                    "Joining domain $DomainName."

                  Add-Computer `
                    -DomainName $DomainName `
                    -Server $AdFqdn `
                    -Credential $DomainCredential `
                    -Force

                  $SecurePassword    = $null
                  $DomainCredential  = $null
                  $DomainJoinSecret  = $null
                  $DomainJoinResponse = $null

                  Write-POCLog `
                    "Domain join completed. Restarting."

                  Restart-Computer `
                    -Force

                  exit 0
              }


              ############################################
              # Validate Domain Join
              ############################################

              $ComputerSystem = Get-CimInstance `
                Win32_ComputerSystem

              if (
                  -not $ComputerSystem.PartOfDomain
              ) {

                  throw `
                    "WSUS server is not joined to the domain."
              }

              Write-POCLog `
                "Domain membership validated."


              ############################################
              # Stage 4
              # Install WSUS Roles
              ############################################

              $WsusFeature = Get-WindowsFeature `
                UpdateServices

              if (
                  $WsusFeature.InstallState -ne "Installed"
              ) {

                  Write-POCLog `
                    "Installing WSUS roles."

                  $FeatureResult = Install-WindowsFeature `
                    UpdateServices, `
                    UpdateServices-WidDB, `
                    UpdateServices-Services `
                    -IncludeManagementTools

                  if (-not $FeatureResult.Success) {

                      throw `
                        "WSUS role installation failed."
                  }

                  if (
                      $FeatureResult.RestartNeeded -eq "Yes"
                  ) {

                      Write-POCLog `
                        "Restart required after WSUS role installation."

                      Restart-Computer `
                        -Force

                      exit 0
                  }
              }


              ############################################
              # Stage 5
              # WSUS Post-Install
              ############################################

              New-Item `
                -Path $WsusContentDir `
                -ItemType Directory `
                -Force |
                Out-Null

              $WsusUtil = `
                "$env:ProgramFiles\Update Services\Tools\WsusUtil.exe"

              if (
                  -not (Test-Path $WsusUtil)
              ) {

                  throw `
                    "WsusUtil.exe not found."
              }

              Write-POCLog `
                "Running WSUS post-install."

              & $WsusUtil `
                postinstall `
                "CONTENT_DIR=$WsusContentDir"

              if (
                  $LASTEXITCODE -ne 0
              ) {

                  throw `
                    "WSUS post-install failed."
              }


              ############################################
              # Stage 6
              # Configure WSUS
              ############################################

              Import-Module `
                UpdateServices

              $WsusServer = Get-WsusServer

              if (
                  $null -eq $WsusServer
              ) {

                  throw `
                    "Unable to connect to local WSUS server."
              }


              ############################################
              # Configure Proxy
              ############################################

              $WsusConfig = `
                $WsusServer.GetConfiguration()

              $WsusConfig.UseProxy        = $true
              $WsusConfig.ProxyName       = $ProxyIP
              $WsusConfig.ProxyServerPort = $ProxyPort

              $WsusConfig.Save()

              Write-POCLog `
                "WSUS proxy configured."


              ############################################
              # Microsoft Update Upstream
              ############################################

              Set-WsusServerSynchronization `
                -UpdateServer $WsusServer `
                -SyncFromMU

              Write-POCLog `
                "WSUS configured to synchronize from Microsoft Update."


              ############################################
              # Update Classifications
              ############################################

              $WantedClassifications = @(
                  "Critical Updates",
                  "Security Updates",
                  "Update Rollups"
              )

              Get-WsusClassification `
                -UpdateServer $WsusServer |
                Where-Object {
                    $_.Classification.Title `
                      -in $WantedClassifications
                } |
                Set-WsusClassification

              Write-POCLog `
                "WSUS classifications configured."


              ############################################
              # Products
              #
              # POC target: Windows Server 2022
              ############################################

              $Products = Get-WsusProduct `
                -UpdateServer $WsusServer

              $WindowsServer2022Products = `
                $Products |
                Where-Object {
                    $_.Product.Title `
                      -like "*Windows Server 2022*"
                }

              if (
                  $null -ne $WindowsServer2022Products
              ) {

                  $WindowsServer2022Products |
                    Set-WsusProduct
              }
              else {

                  Write-POCLog `
                    "Windows Server 2022 product category not found yet; initial sync may populate it."
              }


              ############################################
              # Automatic Approval Rule
              #
              # Critical + Security Updates
              # All Computers
              ############################################

              $RuleName = `
                "Peter POC - Critical and Security Updates"

              $ExistingRule = `
                $WsusServer.GetInstallApprovalRules() |
                Where-Object {
                    $_.Name -eq $RuleName
                } |
                Select-Object `
                  -First 1

              if (
                  $null -eq $ExistingRule
              ) {

                  $ApprovalRule = `
                    $WsusServer.CreateInstallApprovalRule(
                      $RuleName
                    )
              }
              else {

                  $ApprovalRule = `
                    $ExistingRule
              }

              $ClassificationCollection = `
                New-Object `
                  Microsoft.UpdateServices.Administration.UpdateClassificationCollection

              $WsusServer.GetUpdateClassifications() |
                Where-Object {
                    $_.Title -in @(
                      "Critical Updates",
                      "Security Updates"
                    )
                } |
                ForEach-Object {
                    $ClassificationCollection.Add(
                      $_
                    )
                }

              $TargetGroupCollection = `
                New-Object `
                  Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection

              $AllComputersGroup = `
                $WsusServer.GetComputerTargetGroups() |
                Where-Object {
                    $_.Name -eq "All Computers"
                } |
                Select-Object `
                  -First 1

              if (
                  $null -eq $AllComputersGroup
              ) {

                  throw `
                    "WSUS All Computers group not found."
              }

              $TargetGroupCollection.Add(
                $AllComputersGroup
              )

              $ApprovalRule.SetUpdateClassifications(
                $ClassificationCollection
              )

              $ApprovalRule.SetComputerTargetGroups(
                $TargetGroupCollection
              )

              $ApprovalRule.Enabled = $true
              $ApprovalRule.Save()

              Write-POCLog `
                "WSUS automatic approval rule configured."

              # Auto-approval rules apply to newly synchronized
              # updates. ApplyRule also evaluates existing updates.
              $ApprovalRule.ApplyRule()


              ############################################
              # Stage 7
              # Initial Synchronization
              ############################################

              Write-POCLog `
                "Starting initial WSUS synchronization."

              $Subscription = `
                $WsusServer.GetSubscription()

              $Subscription.StartSynchronization()


              ############################################
              # Wait for Synchronization
              ############################################

              for ($i = 1; $i -le 180; $i++) {

                  $Status = `
                    $Subscription.GetSynchronizationStatus()

                  Write-POCLog `
                    "WSUS synchronization status: $Status"

                  if (
                      $Status.ToString() -eq "NotProcessing"
                  ) {

                      break
                  }

                  Start-Sleep `
                    -Seconds 30
              }


              ############################################
              # Validate WSUS Services
              ############################################

              $WsusService = Get-Service `
                -Name WsusService `
                -ErrorAction Stop

              if (
                  $WsusService.Status -ne "Running"
              ) {

                  Start-Service `
                    -Name WsusService
              }


              ############################################
              # Completed
              ############################################

              "WSUS bootstrap completed successfully." |
                Out-File `
                  -FilePath $CompleteFlag `
                  -Encoding ascii `
                  -Force

              Write-POCLog `
                "WSUS bootstrap completed successfully."

              </powershell>

              <persist>true</persist>

              <powershellArguments>
              -ExecutionPolicy Bypass -NoProfile -NonInteractive
              </powershellArguments>

              EOF

  tags = {
    Name = "peter-poc-wsus01"
    Tier = "WSUS"
  }
}


############################################
# Outputs
############################################

output "wsus_instance_id" {
  description = "WSUS EC2 instance ID"
  value       = aws_instance.wsus.id
}

output "wsus_private_ip" {
  description = "WSUS private IP"
  value       = aws_instance.wsus.private_ip
}

############################################
# WSUS Domain Join Secret
############################################

data "aws_secretsmanager_secret" "wsus_domain_join" {
  name = "peter-poc/ad/domain-join"
}

############################################
# WSUS EC2 IAM Role
############################################

resource "aws_iam_role" "wsus" {
  name = "peter-poc-wsus-role"

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

  permissions_boundary = "arn:aws:iam::266170445194:policy/PermissionsBoundary"

  tags = {
    Name = "peter-poc-wsus-role"
  }
}

############################################
# WSUS Secret Read Policy
############################################

resource "aws_iam_role_policy" "wsus_secret_read" {
  name = "peter-poc-wsus-secret-read"
  role = aws_iam_role.wsus.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadDomainJoinSecret"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = data.aws_secretsmanager_secret.wsus_domain_join.arn
      }
    ]
  })
}

############################################
# WSUS Instance Profile
############################################

resource "aws_iam_instance_profile" "wsus" {
  name = "peter-poc-wsus-instance-profile"
  role = aws_iam_role.wsus.name
}
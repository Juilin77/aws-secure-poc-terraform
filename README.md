# AWS Secure Infrastructure POC with Terraform

Terraform-based AWS infrastructure Proof of Concept (POC) demonstrating a security-focused multi-tier architecture with controlled ingress and egress, internal package repository services, database connectivity, monitoring, and repeatable Infrastructure as Code deployment.

## Architecture Overview

The POC implements a multi-tier AWS architecture with separate ingress and egress security paths.

### Ingress Traffic Flow

```text
Internet
   |
   v
Internet Gateway
   |
   v
AWS Network Firewall
   |
   v
AWS WAF
   |
   v
Application Load Balancer
   |
   v
Reverse Proxy
   |
   v
Web Tier
   |
   v
Application Tier
   |
   v
Amazon RDS MySQL
```

The ingress design provides multiple security and application layers before traffic reaches the database tier.

### Controlled Egress Traffic Flow

```text
Application / Repository Server
   |
   v
Forward Proxy
   |
   v
NAT Instance
   |
   v
AWS Network Firewall
   |
   v
Internet Gateway
   |
   v
Internet
```

Application workloads do not rely on unrestricted direct Internet access.

The Forward Proxy provides explicit outbound proxy access, while the NAT instance performs source NAT before traffic passes through AWS Network Firewall.

## Main AWS Components

The environment includes:

- Amazon VPC
- Public and private subnets
- Dedicated AWS Network Firewall subnets
- Dedicated Forward Proxy subnet
- Dedicated NAT instance subnet
- Internet Gateway
- Application Load Balancer
- AWS WAF
- AWS Network Firewall
- Amazon EC2 Instance Connect Endpoint
- Reverse Proxy EC2
- Web Tier EC2
- Application Tier EC2
- Internal Repository EC2
- Forward Proxy EC2
- NAT EC2
- Amazon RDS MySQL
- AWS Secrets Manager managed RDS master password
- Amazon CloudWatch alarms
- VPC Flow Logs
- ALB access logging
- Amazon SNS
- AWS Certificate Manager
- Amazon Route 53

## Terraform File Structure

```text
.
├── acm.tf
├── alb-logs.tf
├── alb.tf
├── cloudwatch-alarms.tf
├── ec2-app.tf
├── ec2-forward-proxy.tf
├── ec2-nat.tf
├── ec2-repo.tf
├── ec2-reverse-proxy.tf
├── ec2-web.tf
├── eice.tf
├── flowlogs.tf
├── iam.tf
├── nacl.tf
├── network-firewall.tf
├── outputs.tf
├── providers.tf
├── rds.tf
├── route53.tf
├── security-groups.tf
├── sns.tf
├── variables.tf
├── versions.tf
├── vpc.tf
└── waf.tf
```

## Network Design

The POC uses the following logical network ranges:

```text
VPC                  10.10.0.0/16

Public Subnet A      10.10.1.0/24
Public Subnet B      10.10.2.0/24

Private Subnet A     10.10.11.0/24
Private Subnet B     10.10.12.0/24

Firewall Subnet A    10.10.21.0/28
Firewall Subnet B    10.10.22.0/28

NAT Subnet A         10.10.31.0/28

Forward Proxy Subnet 10.10.41.0/28
```

## Application Architecture

The application path is:

```text
ALB
 |
 v
Reverse Proxy
 |
 v
Web Tier
 |
 v
Application Tier
 |
 v
RDS MySQL
```

The application EC2 instance does not accept direct application traffic from the ALB.

Each tier uses Security Groups to restrict permitted traffic between adjacent components.

## Database Tier

Amazon RDS MySQL is deployed privately.

Key characteristics include:

- No public database access
- Encrypted storage
- Private DB subnet group
- TCP/3306 restricted to the Application Tier
- Master password managed by AWS Secrets Manager
- Database connectivity protected by Security Groups and Network ACL rules

The following functional test has been validated:

```text
Application EC2
     |
     | TCP/3306
     v
Amazon RDS MySQL
```

Database testing successfully verified:

- TCP connectivity
- Authentication
- Database creation
- Table creation
- INSERT operation
- SELECT operation

Example test:

```sql
CREATE DATABASE IF NOT EXISTS peterpoc;

USE peterpoc;

CREATE TABLE IF NOT EXISTS poc_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO poc_test (message)
VALUES ('App to RDS functional test successful');

SELECT * FROM poc_test;
```

## Internal Package Repository

The Repository EC2 instance provides an internal HTTPS DNF/YUM repository.

The repository bootstrap process automatically:

1. Obtains the Forward Proxy private IP through Terraform.
2. Waits for Forward Proxy connectivity.
3. Installs repository management tools.
4. Downloads the test RPM package.
5. Generates YUM/DNF repository metadata.
6. Starts the internal HTTPS repository service.
7. Validates `repodata/repomd.xml`.

Example repository contents:

```text
/opt/peter-repo/packages/
├── tree-*.rpm
└── repodata/
    └── repomd.xml
```

The Application Tier automatically creates an internal repository configuration similar to:

```ini
[peter-poc]
name=Peter POC Internal Repository
baseurl=https://<repository-private-ip>/packages/
enabled=1
gpgcheck=0
sslverify=0
```

The following test has been validated:

```bash
sudo dnf install -y tree \
  --disablerepo='*' \
  --enablerepo='peter-poc'
```

This verifies that the Application Tier can install packages from the internal repository.

## Forward Proxy

The Forward Proxy provides controlled outbound Internet access for private workloads.

Traffic flow:

```text
Private EC2
   |
   | TCP/3128
   v
Forward Proxy
   |
   v
NAT Instance
   |
   v
AWS Network Firewall
   |
   v
Internet
```

Terraform dynamically provides the Forward Proxy private IP to dependent EC2 bootstrap scripts.

This avoids hard-coded private IP addresses after infrastructure rebuilds.

## NAT Instance

A NAT instance is used for the POC because NAT Gateway creation is restricted in the target AWS environment.

Key configuration includes:

- Dedicated NAT subnet
- Elastic IP
- Source/destination check disabled
- IPv4 forwarding enabled
- iptables MASQUERADE
- Dynamically detected EC2 network interface
- Default route through AWS Network Firewall

The NAT bootstrap dynamically detects the active network interface instead of assuming `eth0`.

## AWS Network Firewall

AWS Network Firewall is deployed in dedicated firewall subnets.

The firewall is inserted into both ingress and egress routing paths.

Current POC policies are primarily designed to validate connectivity and architecture.

They should not be interpreted as final production firewall policy.

## AWS WAF

AWS WAF is associated with the Application Load Balancer.

The WAF provides Layer 7 inspection before application traffic reaches the Reverse Proxy and downstream application tiers.

## Security Groups

Security Groups enforce tier-specific connectivity.

Examples include:

```text
ALB
  -> Reverse Proxy

Reverse Proxy
  -> Web Tier

Web Tier
  -> Application Tier

Application Tier
  -> RDS TCP/3306

Application Tier
  -> Repository TCP/443

Application / Web / Repository
  -> Forward Proxy TCP/3128
```

Security Groups are used as the primary stateful workload-level network control.

## Network ACLs

Custom Network ACL rules are used to provide additional subnet-level traffic restrictions.

Because Network ACLs are stateless, both request and return paths must be explicitly permitted.

For example, Application Tier to RDS requires:

```text
App -> RDS
TCP/3306

RDS -> App
TCP ephemeral return ports
```

## Monitoring and Logging

The POC includes infrastructure monitoring and logging capabilities such as:

- VPC Flow Logs
- CloudWatch Logs
- CloudWatch alarms
- SNS notifications
- ALB access logs
- AWS Network Firewall FLOW logs
- AWS Network Firewall ALERT logs

## Prerequisites

Before deployment:

- Terraform installed
- AWS CLI installed
- Valid AWS authentication
- Required IAM permissions
- Terraform-compatible AWS credentials

Example:

```powershell
aws login --profile peter-poc

$env:AWS_PROFILE="peter-poc-tf"
$env:AWS_REGION="ap-southeast-1"

aws sts get-caller-identity
```

## Configuration

Copy the example variables file and set the required value:

```bash
cp terraform.tfvars.example terraform.tfvars
```

| Variable | Required | Description |
|---|---|---|
| `app_ami_id` | Yes | AMI ID for the application tier EC2 instance (no default) |
| `aws_region`, `vpc_cidr`, subnet/AZ variables | No | Have defaults in `variables.tf`; override in `terraform.tfvars` only if needed |

`terraform.tfvars` is gitignored and must never be committed.

## Terraform Deployment

Initialize Terraform:

```bash
terraform init
```

Format the configuration:

```bash
terraform fmt -recursive
```

Validate:

```bash
terraform validate
```

Review changes:

```bash
terraform plan
```

Deploy:

```bash
terraform apply
```

## Post-Deployment Validation

### Terraform

```bash
terraform validate
terraform plan
```

After a successful deployment and validation, Terraform should not report unexpected infrastructure drift.

### Repository Server

Verify repository metadata:

```bash
find /opt/peter-repo/packages -maxdepth 2 -type f | sort
```

Expected content includes:

```text
tree-*.rpm
repodata/repomd.xml
```

### Application Repository Configuration

```bash
cat /etc/yum.repos.d/peter-poc.repo
```

### Internal Package Installation

```bash
sudo dnf makecache \
  --disablerepo='*' \
  --enablerepo='peter-poc'
```

```bash
sudo dnf install -y tree \
  --disablerepo='*' \
  --enablerepo='peter-poc'
```

### Database Client

```bash
mysql --version
```

The MariaDB client is automatically installed during Application EC2 bootstrap using the Forward Proxy.

### RDS Connectivity

```bash
timeout 5 bash -c \
'cat < /dev/null > /dev/tcp/<rds-endpoint>/3306' \
&& echo "RDS 3306 SUCCESS" \
|| echo "RDS 3306 FAILED"
```

### Application Path

Validate external application access and confirm an HTTP 200 response.

The expected end-to-end path is:

```text
Internet
 -> Network Firewall
 -> WAF
 -> ALB
 -> Reverse Proxy
 -> Web
 -> Application
```

## Destroy and Rebuild Validation

One of the major objectives of the POC is infrastructure reproducibility.

A full validation cycle consists of:

```bash
terraform destroy
```

followed by:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

A successful rebuild should require no manual configuration for:

- Forward Proxy IP configuration
- Repository proxy configuration
- Repository tool installation
- RPM download
- Repository metadata creation
- Application repository configuration
- MariaDB client installation

The rebuilt environment should be validated using the tests documented above.

## Files That Must Not Be Committed

The following generated or sensitive Terraform files should not be stored in Git:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
```

Terraform state may contain infrastructure identifiers and sensitive resource attributes.

Terraform plan files are environment-specific execution artifacts and may also contain sensitive information.

## Recommended `.gitignore`

```gitignore
# Terraform working directory
.terraform/

# Terraform state
*.tfstate
*.tfstate.*

# Terraform plan files
*.tfplan

# Terraform variable files
*.tfvars
*.tfvars.json

# Terraform crash logs
crash.log
crash.*.log

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Local development files
.DS_Store
Thumbs.db
.vscode/
.idea/
```

The following file should normally be committed:

```text
.terraform.lock.hcl
```

It provides Terraform provider dependency version and checksum consistency.

## POC Security Notes

This project is a Proof of Concept and includes implementation choices that should be reviewed before production deployment.

Examples include:

- Self-signed TLS certificates
- `sslverify=0` for the internal POC repository
- Python-based Reverse and Forward Proxy implementations
- NAT instance instead of managed NAT Gateway
- Single-AZ components
- POC-oriented Network Firewall rules
- Repository packages are not currently managed using a production package-signing process

These are acceptable for functional POC validation but should be replaced or hardened before production use.

## Production Recommendations

For production implementation, consider:

- Trusted internal PKI certificates
- Package signature and repository metadata validation
- Production-grade reverse proxy software or managed services
- Production-grade forward proxy such as Squid or an approved enterprise proxy solution
- Multi-AZ database deployment
- High-availability egress design
- Hardened Network Firewall rules
- Centralized logging and SIEM integration
- Remote Terraform state with locking and encryption
- CI/CD Terraform validation and security scanning
- IAM least privilege
- Automated configuration and compliance validation
- Backup and recovery validation

## Compliance Positioning

The POC is designed with security controls that can support alignment with applicable:

- CIS AWS Foundations Benchmark requirements
- Singapore Government IM8 requirements
- Internal security architecture requirements

Formal compliance should only be claimed after completing an explicit control-by-control mapping and compliance validation.

Therefore, the appropriate wording for this POC is:

> Designed to align with applicable CIS AWS Benchmark and GovTech IM8 requirements, subject to formal control mapping and compliance validation.

## Current Validation Status

```text
AWS WAF                         Validated
AWS Network Firewall            Validated
Application Load Balancer       Validated
Reverse Proxy                   Validated
Web Tier                        Validated
Application Tier                Validated
RDS MySQL                       Validated
App -> RDS functional test      Validated
Forward Proxy                   Validated
NAT Instance                    Validated
Internal Repository             Validated
DNF package installation        Validated
Repository automation           Implemented
App repository automation       Implemented
MariaDB client automation       Implemented
Full destroy/rebuild test       Pending final validation
```

## Purpose

This repository demonstrates how Terraform can be used to create a repeatable AWS infrastructure POC with layered network security, workload segmentation, controlled ingress and egress, internal repository services, database isolation, monitoring, and automated bootstrap configuration.
# AWS Secure Infrastructure POC with Terraform

Terraform-based AWS infrastructure Proof of Concept (POC) demonstrating a security-focused multi-tier architecture with controlled ingress and egress, internal package repository services, database connectivity, Windows infrastructure services, monitoring, and repeatable Infrastructure as Code deployment.

## Table of Contents

- [AWS Services Used](#aws-services-used)
- [Architecture Overview](#architecture-overview)
- [Architecture Components](#architecture-components)
- [Terraform File Structure](#terraform-file-structure)
- [Network Design](#network-design)
- [Application Architecture](#application-architecture)
- [Database Tier](#database-tier)
- [Internal Package Repository](#internal-package-repository)
- [Forward Proxy](#forward-proxy)
- [NAT Instance](#nat-instance)
- [AWS Network Firewall](#aws-network-firewall)
- [AWS WAF](#aws-waf)
- [Security Groups](#security-groups)
- [Network ACLs](#network-acls)
- [Active Directory and WSUS](#active-directory-and-wsus)
- [Monitoring and Logging](#monitoring-and-logging)
- [IAM and Permission Constraints](#iam-and-permission-constraints)
- [KMS Governance](#kms-governance)
- [Planned Governance and Security Services](#planned-governance-and-security-services)
- [Architecture Diagrams](#architecture-diagrams)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Terraform Deployment](#terraform-deployment)
- [Post-Deployment Validation](#post-deployment-validation)
- [Destroy and Rebuild Validation](#destroy-and-rebuild-validation)
- [Files That Must Not Be Committed](#files-that-must-not-be-committed)
- [Recommended `.gitignore`](#recommended-gitignore)
- [POC Security Notes](#poc-security-notes)
- [Production Recommendations](#production-recommendations)
- [Compliance Positioning](#compliance-positioning)
- [Current Validation Status](#current-validation-status)
- [Purpose](#purpose)

## AWS Services Used

| Service | Role in this POC |
|---|---|
| Amazon VPC | Network foundation: public/private/firewall/NAT/proxy subnets, route tables, Network ACLs |
| Amazon EC2 | Reverse Proxy, Web, Application, Internal Repository, Forward Proxy, NAT, AD, WSUS instances |
| Elastic Load Balancing (ALB) | Internet-facing, internal Web, and internal App Application Load Balancers |
| AWS WAF | Layer 7 inspection in front of the Internet-facing ALB |
| AWS Network Firewall | Stateful inspection inserted into both ingress and egress routing paths |
| Amazon EC2 Instance Connect Endpoint (EICE) | Private, browser/CLI-based SSH and RDP access without public IPs or bastion hosts |
| Amazon RDS (MySQL) | Private, encrypted database tier for the Application Tier |
| AWS Secrets Manager | AD bootstrap/domain-join credentials and RDS master credentials |
| AWS Certificate Manager (ACM) | TLS certificates for Application Load Balancers |
| Amazon Route 53 | DNS for the POC domain |
| Amazon CloudWatch | Alarms and log groups for infrastructure monitoring |
| Amazon SNS | Alarm notification delivery |
| VPC Flow Logs | Network-level traffic visibility across the VPC |
| AWS IAM | Roles, instance profiles, and a mandatory permissions boundary for all created roles |
| AWS Key Management Service (KMS) | Encryption for storage and Secrets Manager, using existing keys (new key creation is denied by policy) |
| Terraform | Infrastructure as Code: provisioning, state management, and repeatable destroy/rebuild |

Services evaluated and planned for a later phase (not yet implemented) are listed in [Planned Governance and Security Services](#planned-governance-and-security-services).

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
Internet-facing ALB
   |
   v
Reverse Proxy
   |
   v
Internal Web ALB
   |
   v
Web Tier
   |
   v
Internal App ALB
   |
   v
Application Tier
   |
   v
Amazon RDS MySQL
```

The ingress design provides multiple network security and application layers before traffic reaches the database tier.

### Controlled Egress Traffic Flow

```text
Application / Web / Repository / Windows Workloads
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
Internet Gateway
   |
   v
Internet
```

Application workloads do not rely on unrestricted direct Internet access.

The Forward Proxy provides explicit outbound proxy access, while the NAT instance performs source NAT before traffic passes through AWS Network Firewall.

## Architecture Components

Resource-level detail behind the [AWS Services Used](#aws-services-used) table above. The environment includes:

- Amazon VPC
- Public and private subnets
- Dedicated AWS Network Firewall subnets
- Dedicated Forward Proxy subnet
- Dedicated NAT instance subnet
- Internet Gateway
- Internet-facing and internal Application Load Balancers
- AWS WAF
- AWS Network Firewall
- Amazon EC2 Instance Connect Endpoint
- Reverse Proxy EC2
- Web Tier EC2
- Application Tier EC2
- Internal Repository EC2
- Forward Proxy EC2
- NAT EC2
- Windows Server Active Directory Domain Services EC2 (AD01)
- Windows Server Update Services EC2 (WSUS01)
- Amazon RDS MySQL
- AWS Secrets Manager for AD bootstrap/domain-join credentials and RDS master credentials
- EC2 Windows Key Pair / EC2Launch password retrieval for AD break-glass access
- Amazon CloudWatch alarms
- VPC Flow Logs
- ALB access logging
- AWS Network Firewall FLOW logging
- AWS Network Firewall ALERT logging
- Amazon SNS
- AWS Certificate Manager
- Amazon Route 53

## Terraform File Structure

```text
.
├── acm.tf
├── alb-app.tf
├── alb-logs.tf
├── alb-reverse-proxy.tf
├── alb-web.tf
├── cloudwatch-alarms.tf
├── ec2-ad.tf
├── ec2-app.tf
├── ec2-forward-proxy.tf
├── ec2-nat.tf
├── ec2-repo.tf
├── ec2-reverse-proxy.tf
├── ec2-web.tf
├── ec2-wsus.tf
├── eice.tf
├── flowlogs.tf
├── iam.tf
├── nacl.tf
├── network-firewall.tf
├── outputs.tf
├── providers.tf
├── rds.tf
├── route53.tf
├── sns.tf
├── variables.tf
├── versions.tf
├── vpc-1.tf
└── waf.tf
```

`terraform.tfvars.example` documents required/optional input variables (see [Configuration](#configuration)) and is also committed.

Terraform plan files, state files, local debug exports, and private keys are deployment artifacts and are not part of the Terraform source structure.

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
Internet-facing ALB
 |
 v
Reverse Proxy
 |
 v
Internal Web ALB
 |
 v
Web Tier
 |
 v
Internal App ALB
 |
 v
Application Tier
 |
 v
RDS MySQL
```

Each tier uses Security Groups to restrict permitted traffic between adjacent components.

The externally validated application path is:

```text
Internet
 -> AWS Network Firewall
 -> AWS WAF
 -> Reverse Proxy ALB
 -> Reverse Proxy
 -> Web ALB
 -> Web Tier
 -> App ALB
 -> Application Tier
```

An HTTP 200 response has been successfully validated across this path.

## Database Tier

Amazon RDS MySQL is deployed privately.

Key characteristics include:

- No public database access
- Encrypted storage
- Private DB subnet group
- TCP/3306 restricted to the Application Tier
- Master password managed through AWS Secrets Manager
- Database connectivity protected by Security Groups and Network ACL rules

The following connectivity path has been validated:

```text
Application EC2
     |
     | TCP/3306
     v
Amazon RDS MySQL
```

Database testing has successfully verified:

- TCP/3306 connectivity
- Authentication
- Successful connection to the `peterpoc` database
- TLS-capable client connectivity using `--ssl`
- TLS cipher negotiation

Full CREATE/INSERT/UPDATE/DELETE application-level CRUD validation should be re-run and recorded as final evidence before production-readiness sign-off.

The current POC confirms that TLS can be used for the database connection. Database-side `require_secure_transport` enforcement has not yet been enabled and remains an optional hardening item.

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

The following tests have been validated:

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

This verifies that the Application Tier can install packages from the internal repository without relying on unrestricted Internet package access.

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

A NAT instance is used for the POC because `ec2:CreateNatGateway` is explicitly denied in the target AWS environment.

Key configuration includes:

- Dedicated NAT subnet
- Elastic IP
- Source/destination check disabled
- IPv4 forwarding enabled
- iptables MASQUERADE
- Dynamically detected EC2 network interface
- Default route through AWS Network Firewall

The NAT bootstrap dynamically detects the active network interface instead of assuming `eth0`.

For production, a managed and highly available egress solution should be used where organizational policy permits.

## AWS Network Firewall

AWS Network Firewall is deployed in dedicated firewall subnets.

The firewall is inserted into both ingress and egress routing paths.

Current POC policies are primarily designed to validate connectivity and architecture.

They should not be interpreted as final production firewall policy.

Production implementation requires:

- Explicit rule review
- Least-privilege network policy
- Controlled default actions
- Threat signature validation
- Change management
- Logging and alert integration

## AWS WAF

AWS WAF is associated with the Internet-facing Application Load Balancer.

The WAF provides Layer 7 inspection before application traffic reaches the Reverse Proxy and downstream application tiers.

## Security Groups

Security Groups enforce tier-specific connectivity.

Examples include:

```text
Reverse Proxy ALB
  -> Reverse Proxy

Reverse Proxy
  -> Web ALB

Web ALB
  -> Web Tier

Web Tier
  -> App ALB

App ALB
  -> Application Tier

Application Tier
  -> RDS TCP/3306

Application Tier
  -> Repository TCP/443

Application / Web / Repository / Windows workloads
  -> Forward Proxy TCP/3128

EICE
  -> Windows workloads TCP/3389
```

Security Groups are used as the primary stateful workload-level network control.

## Network ACLs

Custom Network ACL rules provide additional subnet-level traffic restrictions.

Because Network ACLs are stateless, both request and return paths must be explicitly permitted.

Private Subnet A and Private Subnet B include controlled east-west rules required for:

- Internal Application Load Balancer traffic
- AD/WSUS communication
- DNS and domain services
- Return traffic

Security Groups remain the primary workload-level segmentation mechanism.

## Active Directory and WSUS

The POC includes a Windows Server-based Active Directory Domain Services instance and a WSUS instance in private subnets.

Key design points:

- AD01 is deployed in Private Subnet A.
- WSUS01 is deployed in Private Subnet B.
- The intended AD domain is `peterpoc.local`.
- The AD hostname is `PETER-AD01`.
- WSUS is designed to join the domain and use AD DNS.
- AD and WSUS administrative access is private-only through Amazon EC2 Instance Connect Endpoint.
- RDP is not exposed directly to the Internet.
- AD bootstrap credentials are stored in AWS Secrets Manager.
- Security Groups provide the primary stateful segmentation control between EICE, AD, WSUS, and private workloads.
- Network ACLs provide the required private-subnet east-west paths.

### AD Break-Glass Access

AD01 now uses an EC2 Windows Key Pair for break-glass access.

```text
Windows EC2 launch
        |
        v
EC2Launch / EC2Launch v2
        |
        v
Generated local Administrator password
        |
        v
EC2 GetPasswordData
        |
        v
Decrypt using private key
        |
        v
EICE
        |
        v
RDP
        |
        v
Local Administrator
```

This recovery path is intentionally independent of:

- AD DS promotion
- Domain credentials
- Forward Proxy connectivity
- Guest-OS access to AWS Secrets Manager

The EC2 private key is a break-glass credential and must:

- Never be committed to Git
- Never be stored in Terraform state
- Be access controlled
- Be securely backed up according to organizational credential-management policy

### Current AD/WSUS Validation State

Terraform replacement and deployment of AD01 and WSUS01 has been validated.

The current AD and WSUS instances are dynamically assigned new private IP addresses after replacement, confirming that dependent Terraform configuration does not rely on hard-coded instance IP addresses.

Remaining validation includes:

- EC2Launch-generated Administrator password retrieval
- Successful EICE/RDP local Administrator login
- Review of `C:\PeterPOC\ad-bootstrap.log`
- Successful AD DS forest promotion
- AD DNS operation
- ADWS, DNS, KDC and Netlogon service validation
- `peterpoc.local` domain validation
- WSUS domain join
- WSUS post-install configuration
- WSUS synchronization and product/classification validation

Until these checks pass, AD/WSUS should be treated as implemented but not fully validated.

## Monitoring and Logging

The POC currently includes:

- VPC Flow Logs
- CloudWatch Logs
- CloudWatch alarms
- SNS notifications
- ALB access logs
- AWS Network Firewall FLOW logs
- AWS Network Firewall ALERT logs

Additional governance and security capabilities identified for the next implementation phase include:

- AWS CloudTrail
- AWS Config
- Amazon GuardDuty
- AWS Security Hub CSPM
- Applicable CIS AWS Foundations Benchmark checks
- AWS Backup

These services are intended to strengthen:

- Auditability
- Configuration-history evidence
- Drift detection
- Threat detection
- Security posture management
- Backup and recovery capability

## IAM and Permission Constraints

The target AWS environment applies organizational IAM controls and a permissions boundary.

Known restrictions include:

```text
ec2:CreateNatGateway       explicitDeny
ec2:CreateVpcEndpoint      explicitDeny
kms:CreateKey              explicitDeny
```

The architecture therefore uses:

- A NAT instance instead of NAT Gateway
- Controlled proxy-based egress instead of SSM/Secrets Manager VPC endpoints
- Existing approved KMS keys or AWS-managed keys instead of creating a new customer-managed KMS key

Infrastructure design must respect organizational IAM boundaries rather than attempting to bypass them.

## KMS Governance

The deployment role cannot create new KMS keys.

Current permission validation:

```text
kms:CreateKey                       explicitDeny
kms:DescribeKey                     allowed
kms:Encrypt                         allowed
kms:Decrypt                         allowed
kms:GenerateDataKey                 allowed
kms:GenerateDataKeyWithoutPlaintext allowed
kms:CreateGrant                     allowed
kms:ListAliases                     allowed
kms:ListKeys                        allowed
```

Existing AWS-managed and customer-managed KMS keys are available.

Existing customer-managed keys must not automatically be reused solely because they are technically accessible.

Before a shared customer-managed KMS key is used, validate:

- Ownership
- Intended purpose
- Key policy
- Service principal permissions
- Encryption context restrictions
- Operational ownership
- Impact on existing workloads

Current design rule:

> Do not create a new KMS key. Use an approved existing customer-managed key or an AWS-managed key, subject to key-policy and service compatibility validation.

## Planned Governance and Security Services

Permission testing indicates that the deployment role can perform the core actions required for:

```text
AWS CloudTrail      Allowed
AWS Config          Allowed
Amazon GuardDuty    Allowed
AWS Security Hub    Allowed
AWS Backup          Allowed
```

These services are planned as the next security and compliance-evidence phase.

### AWS CloudTrail

Planned purpose:

- AWS API activity auditing
- IAM and resource-change visibility
- Security investigation evidence
- Central audit logging

CloudTrail should use protected log storage with encryption, versioning, restricted access and appropriate retention.

### AWS Config

Planned purpose:

- Resource configuration history
- Configuration drift detection
- Security baseline evidence
- Applicable compliance-rule evaluation

Example control areas include:

- Encryption
- Public exposure
- Logging
- Security Groups
- RDS configuration
- S3 configuration

### Amazon GuardDuty

Planned purpose:

- AWS account threat detection
- EC2/network anomaly detection
- IAM credential anomaly detection
- DNS and VPC activity analysis

Findings should integrate with the alerting workflow where practical.

### AWS Security Hub CSPM

Planned purpose:

- Central security findings
- AWS Foundational Security Best Practices
- Applicable CIS AWS Foundations Benchmark visibility
- Remediation tracking

Security Hub results must be reviewed for applicability and regional/service exceptions before being treated as compliance evidence.

### AWS Backup

Planned purpose:

- Centralized backup policy
- Defined backup retention
- Backup vault usage
- Recovery validation

Backup configuration alone is insufficient; restore testing should be included in production-readiness evidence.

## Architecture Diagrams

Diagram sources and exported images live in [`diagrams/`](diagrams/) (`.drawio` source plus `.png` export for each view: `network`, `app`, `dns-edge`, `logging-monitoring-security`, `management`).

The current diagrams predate the multi-tier ALB redesign (separate Reverse Proxy / Web / App ALBs, AD break-glass access) and are being updated to match; treat the [Architecture Overview](#architecture-overview) and [Application Architecture](#application-architecture) text diagrams above as the current source of truth until the images are refreshed.

## Prerequisites

Before deployment:

- Terraform installed
- AWS CLI installed
- Valid AWS authentication
- Required IAM permissions
- Terraform-compatible AWS credentials
- Required Secrets Manager secrets created
- Required EC2 break-glass key pair securely available

Example authentication:

```powershell
aws login --profile peter-poc

$env:AWS_PROFILE="peter-poc-tf"
$env:AWS_REGION="ap-southeast-1"

aws sts get-caller-identity
```

## Configuration

Copy the example variables file and set the required values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

| Variable | Required | Description |
|---|---|---|
| `app_ami_id` | Yes | AMI ID for the application tier EC2 instance (no default) |
| `permissions_boundary_arn` | Yes | IAM permissions boundary policy ARN required by the target AWS account (no default) |
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

For significant changes, save and inspect the plan before applying:

```bash
terraform plan -out=change.tfplan
terraform show -no-color change.tfplan
```

Deploy:

```bash
terraform apply
```

or:

```bash
terraform apply change.tfplan
```

Old saved plan files should be removed after successful deployment and validation.

## Post-Deployment Validation

### Terraform

```bash
terraform validate
terraform plan
```

After successful deployment and validation, Terraform should not report unexpected infrastructure drift.

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

The MariaDB client is automatically installed during Application EC2 bootstrap.

### RDS Connectivity

```bash
timeout 5 bash -c \
'cat < /dev/null > /dev/tcp/<rds-endpoint>/3306' \
&& echo "RDS 3306 SUCCESS" \
|| echo "RDS 3306 FAILED"
```

TLS connection:

```bash
mysql \
  --ssl \
  -h <rds-endpoint> \
  -u <username> \
  -p
```

### Application Path

Validate external application access and confirm an HTTP 200 response.

Expected end-to-end path:

```text
Internet
 -> Network Firewall
 -> WAF
 -> Reverse Proxy ALB
 -> Reverse Proxy
 -> Web ALB
 -> Web
 -> App ALB
 -> Application
```

### AD Break-Glass Access

Retrieve the local Administrator password using the key pair associated with AD01:

```powershell
aws ec2 get-password-data `
  --instance-id <ad-instance-id> `
  --priv-launch-key "$HOME\.ssh\peter-poc-ad-breakglass.pem" `
  --region ap-southeast-1 `
  --profile peter-poc-tf
```

Create the EICE RDP tunnel:

```powershell
aws ec2-instance-connect open-tunnel `
  --instance-id <ad-instance-id> `
  --instance-connect-endpoint-id <eice-id> `
  --remote-port 3389 `
  --local-port 13389 `
  --profile peter-poc-tf
```

Connect:

```powershell
mstsc /v:127.0.0.1:13389
```

Use the local Windows Administrator account rather than domain credentials for break-glass validation.

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

A successful rebuild should require no manual workload configuration for:

- Forward Proxy IP configuration
- Repository proxy configuration
- Repository tool installation
- RPM download
- Repository metadata creation
- Application repository configuration
- MariaDB client installation
- AD/WSUS instance addressing

Externally managed prerequisites such as Secrets Manager values and the EC2 break-glass private key remain outside normal Terraform resource recreation.

The rebuilt environment must be validated using the tests documented above.

## Files That Must Not Be Committed

The following generated or sensitive files should not be stored in Git:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.pem
```

Terraform state may contain infrastructure identifiers and sensitive resource attributes.

Terraform plan files are environment-specific execution artifacts and may also contain sensitive information.

Private key files such as the AD break-glass EC2 key must never be committed.

## Recommended `.gitignore`

```gitignore
# Terraform working directory
.terraform/

# Terraform state
*.tfstate
*.tfstate.*

# Terraform plan files
*.tfplan

# Private keys
*.pem

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

This project is a Proof of Concept and includes implementation choices that must be reviewed before production deployment.

Examples include:

- Self-signed TLS certificates
- `sslverify=0` for the internal POC repository
- Python-based Reverse and Forward Proxy implementations
- NAT instance instead of managed NAT Gateway
- Single-AZ components
- POC-oriented Network Firewall rules
- Repository packages are not currently managed using a production package-signing process
- AD/WSUS validation is still in progress
- RDS TLS is supported but database-side `require_secure_transport` enforcement is not currently enabled
- CloudTrail, AWS Config, GuardDuty, Security Hub CSPM and AWS Backup are planned but not yet implemented

These choices are acceptable for functional POC validation where explicitly documented, but must be replaced, hardened, or formally accepted before production use.

## Production Recommendations

For production implementation, consider:

- Trusted internal PKI certificates
- Package signature and repository metadata validation
- Production-grade reverse proxy software or managed services
- Production-grade forward proxy such as Squid or an approved enterprise proxy
- Multi-AZ database deployment
- High-availability egress design
- Hardened Network Firewall rules
- Enforced TLS where required
- Centralized logging and SIEM integration
- AWS CloudTrail
- AWS Config
- Amazon GuardDuty
- AWS Security Hub CSPM
- AWS Backup with tested restores
- Approved centralized KMS key usage
- Remote Terraform state with locking and encryption
- CI/CD Terraform validation and security scanning
- IAM least privilege
- Automated configuration and compliance validation
- Backup and recovery validation
- Operational runbooks
- Break-glass credential governance
- Monitoring and alert-response procedures

## Compliance Positioning

The POC is designed with security controls that can support alignment with applicable:

- CIS AWS Foundations Benchmark requirements
- Singapore Government IM8 requirements
- Internal security architecture requirements

Formal compliance should only be claimed after completing an explicit control-by-control mapping and compliance validation.

Deployment of an AWS security service by itself does not constitute compliance.

Therefore, the appropriate wording for this POC remains:

> Designed to align with applicable CIS AWS Benchmark and GovTech IM8 requirements, subject to formal control mapping and compliance validation.

## Current Validation Status

```text
AWS WAF                         Validated
AWS Network Firewall            Validated
Application Load Balancers      Validated
Reverse Proxy                   Validated
Web Tier                        Validated
Application Tier                Validated

RDS MySQL connectivity          Validated
RDS authentication              Validated
RDS TLS client connection       Validated
RDS full CRUD test              Pending final evidence

Forward Proxy                   Validated
NAT Instance                    Validated

Internal Repository             Validated
DNF package installation        Validated
Repository automation           Implemented
App repository automation       Implemented
MariaDB client automation       Implemented

EICE configuration              Implemented
EICE RDP client path            Under investigation
AD01 Terraform deployment       Implemented
AD EC2 key-pair break-glass     Implemented
AD local login validation       Pending
AD DS/domain promotion          Pending validation

WSUS Terraform deployment       Implemented
WSUS domain join                Pending validation
WSUS functional validation      Pending validation

VPC Flow Logs                   Implemented
CloudWatch alarms               Implemented
ALB access logging              Implemented
Network Firewall logging        Implemented

AWS CloudTrail                  Planned
AWS Config                      Planned
Amazon GuardDuty                Planned
AWS Security Hub CSPM           Planned
AWS Backup                      Planned

KMS new-key creation            Restricted by policy
Existing KMS key usage          Permitted subject to key policy review

Full destroy/rebuild test       Partially validated
Final AD/WSUS validation        Pending
```

## Purpose

This repository demonstrates how Terraform can be used to create a repeatable AWS infrastructure POC with:

- Layered network security
- Workload segmentation
- Controlled ingress
- Controlled egress
- Internal repository services
- Database isolation
- Private Windows infrastructure services
- Break-glass access design
- Monitoring and logging
- Security governance planning
- Automated bootstrap configuration

The architecture is intended to provide a practical foundation for further CIS AWS Benchmark review, GovTech IM8 control mapping, security validation, operational handover preparation, and production hardening.
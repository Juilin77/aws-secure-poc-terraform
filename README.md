# AWS Secure Infrastructure POC — Terraform

**Region:** `ap-southeast-1` (Singapore)  
**Primary VPC CIDR:** `10.10.0.0/16`  
**Documentation updated:** 19 November 2026 (post-rebuild validation)  
**Status:** Functional ingress and explicit egress confirmed after the final 19 November rebuild, with all four POC target groups reported healthy; bootstrap, security and operational acceptance still require evidence review.

## Purpose and scope

This repository deploys a multi-tier AWS proof of concept (POC) using Terraform. It demonstrates public HTTPS ingress, isolated web/application/database tiers, an internal Squid forward proxy, an Nginx reverse proxy, an internal HTTPS Amazon Linux 2023 (AL2023) RPM repository, EC2-based NAT, AWS Network Firewall, Windows AD/WSUS infrastructure, and supporting monitoring and backup resources.

The design is intended to support review against **applicable CIS AWS Foundations Benchmark** and **Singapore GovTech IM8** requirements. It is **not a certification or declaration of compliance**; control-by-control mapping, findings disposition, operational evidence, and approvals are still required.

## Architecture

### Inbound application traffic

```text
Internet / HTTPS
    |
    v
Internet-facing ALB + AWS WAF
    |
    v
Nginx Reverse Proxy EC2 (HTTPS/443)
    |
    v
Internal Web ALB (HTTPS)
    |
    v
Web EC2
    |
    v
Internal Application ALB (HTTPS)
    |
    v
Application EC2
    |
    v
Private Amazon RDS MySQL (TCP/3306)
```

AWS Network Firewall is integrated into the VPC routing design. Verify its exact forwarding path against deployed route tables; the diagram above describes the logical application path, not every networking hop.

### Explicit outbound HTTP/HTTPS proxy

```text
Approved workload EC2
    |
    | Explicit HTTP proxy / HTTPS CONNECT, TCP/3128
    v
Internal Network Load Balancer (TCP/3128)
    |
    v
Squid Forward Proxy EC2 (TCP/3128)
    |
    | Remote destination IP: TCP/80 or 443
    v
EC2 NAT instance (route-table next hop; source NAT)
    |
    v
AWS Network Firewall / Internet egress routing
    |
    v
Internet
```

An **NLB**, not an ALB, is used for the forward proxy because TLS tunnelling requires HTTP `CONNECT`, which should not be terminated or interpreted by an ALB. The NLB is internal and accepts TCP/3128 only from approved workload security groups.

The forward proxy's security-group outbound destination is `0.0.0.0/0` on **TCP/80 and TCP/443** because security groups evaluate the actual destination IP; the NAT instance is selected by the subnet route table, not by changing the destination to the NAT private IP.

### Internal RPM repository and bootstrapping

```text
AL2023 package source --(Repo EC2 via NAT)--> local RPM mirror + repodata
                                                 |
                                                 | HTTPS/443
                                                 v
                              repo.vpc1.internal /packages/
                                                 |
                                +----------------+----------------+
                                |                                 |
                         Squid bootstrap                   Nginx bootstrap
```

The Repository EC2 downloads `squid`, `nginx`, `openssl`, `tree` and dependencies, generates metadata using `createrepo_c`, and serves the content using a Python HTTPS **repository server** (`peter-repo`). Python is **not** the forward or reverse proxy implementation. This package-server bootstrap depends on AL2023 package-source connectivity; downstream Squid/Nginx installs depend on internal repository readiness.

Both Linux proxy instances use the internal repository with `gpgcheck=1`, `sslverify=1`, and an explicit CA certificate, and wait/retry for repository readiness before package installation. Repository TLS currently uses a fixed, locally generated self-signed certificate (`repo-server.crt` and `repo-server.key`).

**Security warning:** The POC embeds the repository TLS **private key** into Terraform EC2 User Data via `file(...)`. That material can be exposed through Terraform plans/state and authorized EC2 User Data access. Never commit the key, state or plan. Replace this approach with approved secret/certificate provisioning for production.

## Core services and Terraform files

| Area | Main files | Role |
|---|---|---|
| VPC, routing and ACLs | `vpc-1.tf`, `nacl.tf`, `network-firewall.tf` | VPC, subnet isolation, routes, stateless ACLs, firewall |
| Inbound load balancing | `alb-reverse-proxy.tf`, `alb-web.tf`, `alb-app.tf`, `waf.tf`, `acm.tf` | Public/internal ALBs, HTTPS and WAF |
| Reverse proxy | `ec2-reverse-proxy.tf` | Nginx HTTPS/443 to internal Web ALB |
| Forward proxy | `ec2-forward-proxy.tf`, `nlb-forward-proxy.tf` | Squid and internal TCP/3128 NLB |
| Egress and packages | `ec2-nat.tf`, `ec2-repo.tf`, `route53.tf` | NAT EC2, HTTPS RPM repository, private DNS |
| Application and database | `ec2-web.tf`, `ec2-app.tf`, `rds.tf` | Web, app and private MySQL |
| Windows infrastructure | `ec2-ad.tf`, `ec2-wsus.tf`, `eice.tf` | AD DS, WSUS, private administrator access |
| Security/operations | `iam.tf`, `flowlogs.tf`, `alb-logs.tf`, `cloudwatch-alarms.tf`, `sns.tf`, `backup.tf` | IAM, logs, alarms, notifications, backup |
| Terraform configuration | `providers.tf`, `versions.tf`, `variables.tf` | Providers, versions, variables |

Names and IDs may change between rebuilds. In particular, Terraform **security-group `name` changes force replacement**: review any planned SG replacements and their dependencies before applying. Do not treat a `Name` tag update as an actual SG rename.

## Network layout

| Segment | CIDR | AZ / purpose |
|---|---|---|
| VPC | `10.10.0.0/16` | Overall network |
| Public A / B | `10.10.1.0/24`, `10.10.2.0/24` | Public-facing load-balancer and routing components |
| Private A / B | `10.10.11.0/24`, `10.10.12.0/24` | Web, app, proxy and Windows workloads |
| Firewall A / B | `10.10.21.0/28`, `10.10.22.0/28` | AWS Network Firewall endpoints |
| NAT A / B | `10.10.31.0/28`, `10.10.32.0/28` | NAT subnets; verify deployed instance/AZ coverage |
| Forward proxy A / B | `10.10.41.0/28`, `10.10.42.0/28` | Internal NLB/proxy subnet placement |
| Repository | `10.10.14.0/24` (deployed Repo B) | Internal RPM repository |

The deployed forward-proxy service presently uses an instance in the Forward Proxy A subnet; creating two proxy subnets does **not** itself provide two healthy proxy instances or multi-AZ application availability.

## Security model and known limitations

- Security groups provide **stateful** tier-level restrictions. NACLs are **stateless** and require matching request/return rules.
- The forward-proxy EC2 receives TCP/3128 from the NLB security group. The NLB accepts approved application/web/repository/AD/WSUS security groups.
- The reverse-proxy EC2 receives HTTPS/443 from the public reverse-proxy ALB security group and proxies to the internal Web ALB.
- RDS is private; TCP/3306 is restricted to the application tier. Authentication is managed separately from network permission.
- EICE is used for private administrative access; do not open SSH/RDP from `0.0.0.0/0`.
- NAT-instance ingress from the VPC CIDR using all protocols is a **known broad POC rule** requiring source/protocol review before production. A `0.0.0.0/0` HTTP/HTTPS destination on the Squid egress SG is not the same as unrestricted inbound access.
- Review NACL associations, especially subnets falling back to a permissive default NACL; validate ephemeral reply ports before restricting stateless ACLs.
- Nginx's generated backend-proxy configuration presently disables upstream certificate verification (`proxy_ssl_verify off`), which requires remediation for production. The proxy's **DNF repository** TLS verification is separately enabled.
- The repository uses a self-signed fixed certificate and an unsigned metadata index (`repo_gpgcheck=0`); validate upstream package signing and establish approved repository signing/PKI before production.
- NAT instances and other single-instance components are not equivalent to managed multi-AZ HA services.
- Some deployments are restricted by organizational IAM policy (historically including `ec2:CreateNatGateway`, `ec2:CreateVpcEndpoint`, and `kms:CreateKey`). Do not bypass permissions boundaries; use approved alternatives.

## Prerequisites

1. Terraform and AWS CLI installed; authentication authorized for the intended AWS account/region.
2. Access to suitable AMIs and pre-existing/approved credential, key-pair and KMS arrangements, as applicable.
3. A **matching** `repo-server.crt` and `repo-server.key` in the Terraform module root. These are local deployment inputs and are not stored in this public repository.
4. A reviewed deployment plan, adequate AWS quotas, and permission to incur POC charges.

Example local TLS material checks (Git Bash/OpenSSL):

```bash
openssl verify -CAfile repo-server.crt repo-server.crt
openssl x509 -in repo-server.crt -pubkey -noout | openssl sha256
openssl pkey -in repo-server.key -pubout | openssl sha256
```

The two public-key digests must match. The certificate must have a SAN for `repo.vpc1.internal` and be accepted by the client trust configuration. Self-verification alone does not establish production trustworthiness.

## Configuration

Copy the example variables file and set the required values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

| Variable | Required | Description |
|---|---|---|
| `app_ami_id` | Yes | AMI ID for the application tier EC2 instance (no default) |
| `permissions_boundary_arn` | Yes | IAM permissions boundary policy ARN required by the target AWS account (no default) |
| `contact_email` | Yes | Contact email for resource tagging and the SNS alert subscription (no default) |

All subnet CIDRs and availability zones have defaults in `variables.tf`; see `terraform.tfvars.example` for the optional overrides. Never commit `terraform.tfvars`, and never hardcode an account ID or a personal email in `.tf` files.

## Deploy (PowerShell)

```powershell
$env:AWS_REGION = "ap-southeast-1"
aws sts get-caller-identity
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out="poc.tfplan"
terraform show -no-color ".\poc.tfplan"
terraform apply ".\poc.tfplan"
Remove-Item ".\poc.tfplan" -Force
```

Use the correct AWS credential profile for your environment; do not copy another operator's profile names into automation. Treat the saved plan as sensitive and verify all proposed replacements, especially after security-group **name** changes. Check `terraform plan` after deployment for unexpected drift.

### Destructive rebuild

`terraform destroy` is **destructive** and can remove data, instances and recovery-related resources; backups can also prevent automatic vault deletion. Confirm the permitted scope, retention obligations, and approved recovery approach first. Then use a fresh plan and re-run all post-deployment tests. Do not assume manually generated state, credentials, instance IDs or IP addresses will survive rebuilding.

**Observed 19 Nov 2026 destroy blocker:** `DeleteBackupVault` failed for `backupvault-peter-vpc1-ec2-01` because it contained recovery points. AWS Backup recovery-point deletion is permanent; obtain authorization and verify retention/vault-lock requirements before deleting any backups. After resolving a blocked destroy, regenerate the destroy plan rather than reusing a saved plan. The later successful HTTP tests do not, by themselves, establish the backup vault's final state.

## Verification and operational evidence

The commands below are diagnostic and do not modify infrastructure unless explicitly noted.

### 1. Target groups and application path

```powershell
$region = "ap-southeast-1"
$tgs = aws elbv2 describe-target-groups --region $region `
  --query "TargetGroups[?starts_with(TargetGroupName, 'tg-peter-vpc1-')].[TargetGroupName,TargetGroupArn]" `
  --output json | ConvertFrom-Json
foreach ($tg in $tgs) {
  Write-Host "`n$($tg[0])"
  aws elbv2 describe-target-health --region $region `
    --target-group-arn $tg[1] `
    --query "TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}" `
    --output table
}
```

```powershell
curl.exe -v https://poc.ipursuitlab.com/
```

Verify `HTTP 200` and expected `X-Peter-Web-Tier` / `X-Peter-App-Tier` response headers. The public URL is environment-specific; validate DNS/certificate ownership before reuse. A passing HTTP test does not, by itself, prove that every reverse-proxy hop is used.

### 2. Internal RPM repository (Repo EC2)

```bash
sudo cloud-init status --long
sudo systemctl is-active peter-repo
find /opt/peter-repo/packages -maxdepth 1 -name '*.rpm' | wc -l
ls -l /opt/peter-repo/packages/repodata/repomd.xml
sudo journalctl -u peter-repo --no-pager -n 30
```

**Historical observation (18 Nov 2026):** A prior rebuild showed **215 RPM files and an active repository service**, while Repo `cloud-init` still reported `error` from an immediate localhost HTTPS readiness probe. **Separate incident (19 Nov 2026, before the later successful rebuild):** Repo `cloud-init` failed to download AL2023 metadata from the regional S3-backed mirror (`Curl error 28: timeout`), could not install `createrepo_c`, and did not register `peter-repo.service`. A subsequent positive end-to-end HTTP response does **not** independently verify the latest Repo `cloud-init` status or package count. For every new rebuild, verify `cloud-init status: done`, the repository service, and `repomd.xml`.

### 3. Forward proxy (Squid EC2)

```bash
sudo cloud-init status --wait
rpm -q squid
sudo systemctl is-active squid
sudo ss -lntp | grep ':3128'
sudo squid -k parse
sudo tail -n 30 /var/log/squid/access.log
```

From an **approved** application client, using the NLB DNS name from Terraform output:

```bash
curl -I -x http://<forward-proxy-nlb-dns>:3128 https://www.google.com
curl -s -x http://<forward-proxy-nlb-dns>:3128 https://checkip.amazonaws.com
```

Expected: `HTTP/1.1 200 Connection established`, a successful upstream HTTPS response, and an Internet egress IP consistent with the intended NAT EIP. Verify the corresponding Squid access log record. No `-k` is needed when the public site's certificate validates.

### 4. Reverse proxy (Nginx EC2)

```bash
sudo cloud-init status --wait
rpm -q nginx openssl
sudo systemctl is-active nginx
sudo nginx -t
sudo ss -lntp | grep ':443'
sudo nginx -T 2>&1 | grep -E 'listen|proxy_pass|proxy_ssl_verify|upstream'
sudo tail -n 30 /var/log/nginx/peter-reverse-proxy-access.log
```

Confirm a real request reaches the reverse-proxy access log **and** the intended internal Web ALB/backend. This separate reverse-proxy traffic proof was not included in the recorded November tests.

### 5. Database (Application EC2)

```bash
mysql -h <rds-endpoint> -P 3306 -u <authorized-user> -p
```

A successful MySQL login was recorded on 18 November 2026. Production-readiness additionally requires confirmation of TLS enforcement, least-privilege database permissions, and a documented CRUD/restore test.

### 6. Network permissions and operations

```powershell
$vpc = aws ec2 describe-instances --region ap-southeast-1 `
  --filters "Name=tag:Name,Values=ec2-peter-vpc1-repo-*" "Name=instance-state-name,Values=running" `
  --query "Reservations[0].Instances[0].VpcId" --output text
# Verify the returned VPC ID is correct before using it in account-level queries
aws ec2 describe-network-acls --region ap-southeast-1 `
  --filters "Name=vpc-id,Values=$vpc" `
  --query "NetworkAcls[].{ID:NetworkAclId,Default:IsDefault,Subnets:Associations[].SubnetId}" --output json
aws ec2 describe-security-groups --region ap-southeast-1 `
  --filters "Name=vpc-id,Values=$vpc" --output json
```

Before sign-off, capture current evidence for: security groups/NACLs and their associations; target health; AWS Network Firewall policy/logs; VPC Flow Logs; CloudWatch alarms and SNS delivery; CloudTrail/Config/Security Hub/GuardDuty where enabled; AWS Backup vaults, completed recovery points and restore testing; IMDSv2; EBS/RDS encryption; IAM and key governance.

## Validation snapshot — 19 November 2026

**Evidence boundary:** These results are supplied from user-run `curl` and AWS CLI outputs during the 19 November rebuild cycle. They establish tested paths, not a complete audit of all application hosts, target groups, security controls or the current Terraform code deployed on EC2. Earlier 18 November observations remain historical and must not be treated as confirmation for new instances.

| Component or test | 19 Nov observation | Remaining evidence / next action |
|---|---|---|
| Public HTTPS ingress | `curl.exe -vk https://poc.ipursuitlab.com` returned **HTTP/1.1 200 OK** (`19 Nov 2026 12:35:28 GMT`); `Server: nginx`; `X-Peter-Web-Tier: ec2-peter-vpc1-web-1a`, `X-Peter-App-Tier: ec2-peter-vpc1-app-1a`; expected HTML title | Verify ALB target health and correlate reverse-proxy/Web/App logs; public curl used `-k`, which disables certificate verification |
| Explicit Internet egress | App EC2 used the internal forward-proxy NLB (`<forward-proxy-nlb-dns>:3128`); `HTTP/1.1 200 Connection established` then **HTTP/2 200** from `www.google.com` (`19 Nov 2026 12:37:51 GMT`) | Confirm Squid access logs, egress NAT EIP, security-group scope and proxy-deny behavior |
| Four POC target groups | After the final rebuild (bootstrap fix applied), the operator reported **all four target groups healthy** (Reverse Proxy, Web, App, Forward Proxy). An earlier pre-fix check had found App, Web and Reverse Proxy `unused` / `Target.InvalidState` | Keep the `describe-target-health` output as evidence; recheck after every rebuild |
| NAT / Repo bootstrap | Earlier 19 Nov failure: Repo AL2023 package metadata timed out; `createrepo_c` install failed; `peter-repo.service` absent, followed by Squid missing from Forward Proxy | Recheck final NAT/Repo `cloud-init` results, NAT rules persistence, `peter-repo` readiness and installed RPM metadata on new instances |
| Reverse proxy | Public request returned Nginx headers and Web/App identifiers | Independently verify reverse-proxy access logs and backend TLS handling; no fresh `nginx -t` result supplied |
| App / database | Web/App response headers observed via public HTTPS | No fresh post-rebuild authenticated MySQL or CRUD/TLS test supplied; older 18 Nov database test is historical |
| AD / WSUS | Included in Terraform architecture | Post-rebuild validation not supplied: promotion, DNS, domain join, WSUS sync, EICE/RDP |
| Security and monitoring | Terraform files document several controls | Runtime checks, detection/alert delivery, CIS and IM8 control mapping still required |
| AWS Backup | An earlier destroy failed because recovery points remained in `backupvault-peter-vpc1-ec2-01` | Current vault/backup state, retention, recovery-point completion and restore testing not verified |

### Root-cause analysis — 19 November bootstrap failure

The earlier failure affected **four target groups through the same bootstrap dependency chain**, rather than four independent load-balancer misconfigurations:

```text
NAT instance early Internet readiness gate (reported failure; MASQUERADE not yet configured)
    -> Repo EC2: AL2023 metadata timeout, createrepo_c unavailable
    -> Internal HTTPS repository not serving packages
    -> Forward Proxy: squid.service absent, no TCP/3128 listener
    -> App/Web/Reverse Proxy initialization dependent on repository readiness
    -> Forward Proxy + three HTTPS target groups fail or remain unavailable
```

The Repo and Squid failures were supported by EC2 `cloud-init`/`systemctl`/`ss` evidence. The NAT readiness/iptables ordering was identified from source review and fixed in code (see below); deployed NAT bootstrap logs from the failed run were not captured. Do **not** infer that adding an S3 Gateway Endpoint is required: an account-level endpoint found in another VPC cannot establish the Repo VPC's intended egress path.

### Bootstrap hardening — applied 19 November 2026

**Scope: `ec2-nat.tf` and `ec2-repo.tf`.** These changes are in this repository and were present in the Terraform state of the final 19 November rebuild.

- **`ec2-nat.tf`:**
  - `depends_on` on `aws_networkfirewall_firewall.main`, `aws_route.nat_a_internet` and `aws_route.igw_to_nat_a`, so the NAT instance launches only after its egress path exists. (`aws_eip_association.nat` cannot be listed because it depends on the NAT instance.)
  - The early fatal Internet gate was removed. `iptables-services` installation retries up to 40 times; only a failed `iptables` installation is fatal.
  - IPv4 forwarding and MASQUERADE/FORWARD rules are configured before a final, **non-fatal** Internet check.
- **`ec2-repo.tf`:**
  - `depends_on` on `aws_instance.nat`, `aws_route.repo_b_to_nat_a` and `aws_eip_association.nat`.
  - Bounded `dnf makecache --refresh` retry (40 × 15 s) before installing `createrepo_c`; on exhaustion it logs the failure and stops.
  - Bounded retry on the local HTTPS readiness probe of `repomd.xml`.
- **Limits:** `depends_on` waits for AWS resource creation, **not** for cloud-init completion. Downstream Web/App/proxy bootstraps still wait a bounded time for the repository; check cloud-init on every rebuild.
- **Change safety:** run `terraform fmt -check`, `terraform validate`, and review a fresh `terraform plan`. Web, App, proxy, AD and WSUS instances set `user_data_replace_on_change = true`, so a `user_data` change replaces them. NAT and Repo do not: a `user_data` change there only stops/starts the instance and cloud-init does not re-run the script, so use `-replace` when their bootstrap must run again. Do not force-replace instances when live end-to-end tests pass without a reason.

**Verification order:** NAT -> Repo -> Forward Proxy -> App -> Web -> Reverse Proxy, stopping at the first failing dependency. Use EC2 cloud-init logs as needed, then confirm four TG states and repeat inbound/outbound HTTP tests. This is an operational sequence, **not** evidence that each component already passed in the final rebuild.

Do not infer complete CIS/IM8 compliance, high availability, backup recoverability, certificate trust, from these functional tests and target-group health checks.

## Repository hygiene and GitHub publishing

Commit Terraform source, this README, a reviewed `.gitignore`, and `.terraform.lock.hcl`. Do **not** publish credentials, state, saved plans, or environment-specific exported findings. In particular, exclude the repository TLS private key and EC2 break-glass keys.

Recommended `.gitignore` entries:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
*.tfvars.json
*.pem
*.key
*.p12
*.pfx
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.aws/
.DS_Store
Thumbs.db
```

A public certificate such as `repo-server.crt` may be stored in Git **only after reviewing whether exposing its associated hostnames/metadata is acceptable**. If excluded, document certificate generation and secure distribution separately. A generated local certificate/key pair is a deployment prerequisite, not a public sample secret.

The five `securityhub-*.json` files in the working folder are AWS Security Hub `get-findings` query filters, **not Terraform dependencies** unless referenced by a script. Resource-specific filters containing old ARNs can be deleted; the generic failed/active findings filter can optionally be retained as a reusable example. Do not publish raw sensitive findings or account inventory without review.

Before pushing:

```powershell
git status --short
git ls-files "*.tfstate" "*.tfstate.*" "*.tfplan" "*.key" "*.pem" "*.json"
```

`.gitignore` does not untrack files already committed. If secrets or state have appeared in Git history, address history exposure and rotate affected credentials rather than merely deleting the files from the latest commit.

## Production hardening and handover

Priorities include replacing the self-signed certificate/private-key-in-User-Data flow with approved PKI and secret distribution; enabling backend TLS verification; narrowing broad NAT and subnet rules safely; verifying route-table/NACL paths; HA and recovery design; package provenance/signing; automated bootstrap monitoring; encrypted/locked remote Terraform state; security-control evidence and exception tracking; AD/WSUS validation; and documented incident, patching, backup/restore and break-glass runbooks.

The November 10 implementation summary's **ALB forward-proxy** approach was superseded by the November 12 **NLB TCP/3128** design. This README consolidates those changes, the November 18 historical snapshot, and the November 19 bootstrap incident and successful HTTP/HTTPS tests; the historical `CHANGELOG_20261112.md` and `IMPLEMENTATION_SUMMARY.txt` are not required for deploying the current design.

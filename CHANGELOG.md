# Changelog

All notable changes to this POC are recorded here, newest first.

**Repository history reset (19 November 2026):** the Git history was restarted from a single commit so that earlier commits containing environment-specific identifiers are no longer published. The entries below up to 13 November summarise that earlier history.

## 2026-11-19 — Bootstrap hardening, repository reset

### Fixed
- **All four target groups unhealthy after rebuild.** Root cause was one bootstrap dependency chain, not four load-balancer faults:
  NAT exited on an early Internet check before configuring MASQUERADE → Repo could not reach AL2023 package sources → internal RPM repository not served → Squid/Nginx not installed and Web/App bootstrap aborted waiting for the repository.
- `ec2-nat.tf`:
  - `depends_on` Network Firewall and the NAT/IGW routes, so NAT launches after its egress path exists.
  - Removed the fatal early Internet gate; `iptables-services` install now retries (40 attempts), and only a failed `iptables` install is fatal.
  - IPv4 forwarding and NAT rules are configured before a final, non-fatal Internet check.
- `ec2-repo.tf`:
  - `depends_on` the NAT instance, its EIP association and the Repo-B → NAT route.
  - Bounded `dnf makecache --refresh` retry (40 × 15 s) before installing repository tools.
  - Bounded retry on the local HTTPS readiness probe instead of a single-shot check.
- **App and Web to Repo HTTPS:** security-group egress and NACL rules now allow TCP/443 to the Repo subnets (the Repo had moved to the Repo-B subnet).

### Changed
- Web and App bootstrap now install packages from the internal repository (`repo.vpc1.internal`) and wait a bounded time for it.
- Forward-proxy security group rules moved to standalone `aws_security_group_rule` resources.
- README consolidated into a single file, with a Configuration section, the 19 November validation snapshot and root-cause analysis.

### Verified (final 19 November rebuild)
- Public HTTPS endpoint returned HTTP 200 with Web/App tier headers.
- Explicit egress through the internal forward-proxy NLB succeeded.
- All four POC target groups reported healthy.

## 2026-11-17 / 18 — New naming, NLB forward proxy, repository subnet

### Added
- `nlb-forward-proxy.tf`: internal Network Load Balancer on TCP/3128 in front of Squid (replaces the earlier ALB forward-proxy design; HTTPS `CONNECT` must not be terminated by an ALB).
- Dedicated Repository subnets with private DNS `repo.vpc1.internal` (`route53.tf`).
- AZ-B subnets for NAT and forward proxy.
- `backup.tf`: AWS Backup vault, plan and selection for EC2.
- `.terraform.lock.hcl` committed for reproducible provider versions.

### Changed
- Resource naming convention changed from `peter-poc-*` to `<type>-peter-vpc1-<role>-NN`.
- `outputs.tf` removed; outputs now live next to their resources.
- `terraform.tfvars.example` updated for new and renamed variables.
- `.gitignore` tightened (state, plans, tfvars, keys, certificates, operator notes, exported findings).

### Fixed
- Re-parameterised values that had been hardcoded again in the 17 November working copy: the IAM permissions boundary ARN (`var.permissions_boundary_arn`) and the contact email (`var.contact_email`).
- Mis-encoded UTF-8 arrows in ALB file comments.

## 2026-11-13
- Removed the `diagrams/` folder (draw.io sources and PNGs). Updated diagrams will be added later.

## 2026-11-07
- Removed a hardcoded personal email; parameterised as `contact_email`.
- Replaced a hardcoded account-specific permissions boundary ARN with `permissions_boundary_arn`.
- Merged the 6 November POC iteration; restored consistent naming.
- Improved README navigation and AWS service coverage.

## 2026-11-05
- Upgraded the POC to a multi-tier architecture (reverse proxy, web, app, RDS, AD, WSUS, forward proxy, NAT, Network Firewall).
- Fixed stale resource names; added a Configuration section to the README.

## 2026-10-09 / 12
- Added security hardening, parameterised account-specific values, and added diagrams and README.
- Renamed remaining legacy resource prefixes to `peter-poc-*`.

## 2026-09-28
- Initial AWS POC Terraform baseline.

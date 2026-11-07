variable "aws_region" {
  description = "AWS region for the POC"
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet A"
  type        = string
  default     = "10.10.1.0/24"
}

variable "public_subnet_b_cidr" {
  description = "CIDR block for public subnet B"
  type        = string
  default     = "10.10.2.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet A"
  type        = string
  default     = "10.10.11.0/24"
}

variable "private_subnet_b_cidr" {
  description = "CIDR block for private subnet B"
  type        = string
  default     = "10.10.12.0/24"
}

variable "availability_zone_a" {
  description = "Availability Zone A"
  type        = string
  default     = "ap-southeast-1a"
}

variable "availability_zone_b" {
  description = "Availability Zone B"
  type        = string
  default     = "ap-southeast-1b"
}

variable "app_ami_id" {
  description = "Pinned AMI ID for Peter POC application instance"
  type        = string
}

variable "permissions_boundary_arn" {
  description = "IAM permissions boundary policy ARN required by the target AWS account for IAM roles created by this POC"
  type        = string
}

variable "firewall_subnet_a_cidr" {
  description = "CIDR block for Network Firewall subnet A"
  type        = string
  default     = "10.10.21.0/28"
}

variable "firewall_subnet_b_cidr" {
  description = "CIDR block for Network Firewall subnet B"
  type        = string
  default     = "10.10.22.0/28"
}

variable "nat_subnet_a_cidr" {
  description = "CIDR block for NAT instance subnet A"
  type        = string
  default     = "10.10.31.0/28"
}

variable "forward_proxy_subnet_a_cidr" {
  description = "CIDR block for Forward Proxy subnet A"
  type        = string
  default     = "10.10.41.0/28"
}
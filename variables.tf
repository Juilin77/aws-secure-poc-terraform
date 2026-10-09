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

variable "owner_email" {
  description = "Email address for alerts and resource tagging"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the ALB/ACM certificate"
  type        = string
}

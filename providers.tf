provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "peter-poc"
      Environment = "POC"
      ManagedBy   = "Terraform"
      email       = "contact@example.com"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "PETER-POC"
      Environment = "POC"
      ManagedBy   = "Terraform"
    }
  }
}
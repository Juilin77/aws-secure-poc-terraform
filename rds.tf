############################################
# Peter POC - DB Tier
# Amazon RDS MySQL
############################################


############################################
# DB Subnet Group
############################################

resource "aws_db_subnet_group" "main" {
  name = "peter-poc-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "peter-poc-db-subnet-group"
    Tier = "Database"
  }
}


############################################
# Database Security Group
############################################

resource "aws_security_group" "db" {
  name        = "peter-poc-db-sg"
  description = "Security group for Peter POC RDS MySQL"
  vpc_id      = aws_vpc.main.id

  ##########################################
  # App Tier -> MySQL
  ##########################################

  ingress {
    description     = "Allow MySQL from application tier only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  #
  # No outbound rule required for this POC.
  #

  tags = {
    Name = "peter-poc-db-sg"
    Tier = "Database"
  }
}


############################################
# Amazon RDS MySQL
############################################

resource "aws_db_instance" "mysql" {
  identifier = "peter-poc-mysql"

  ##########################################
  # Database Engine
  ##########################################

  engine = "mysql"

  instance_class = "db.t3.micro"

  ##########################################
  # Storage
  ##########################################

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  ##########################################
  # Database
  ##########################################

  db_name  = "peterpoc"
  username = "peteradmin"

  #
  # Let Amazon RDS manage the master password
  # instead of storing the password in TF code.
  #

  manage_master_user_password = true


  ##########################################
  # Network
  ##########################################

  db_subnet_group_name = aws_db_subnet_group.main.name

  vpc_security_group_ids = [
    aws_security_group.db.id
  ]

  publicly_accessible = false

  port = 3306


  ##########################################
  # Availability
  #
  # POC: Single-AZ
  ##########################################

  multi_az = false


  ##########################################
  # Backup
  #
  # Small retention period for POC
  ##########################################

  backup_retention_period = 1


  ##########################################
  # Maintenance
  ##########################################

  auto_minor_version_upgrade = true

  apply_immediately = true


  ##########################################
  # Deletion
  #
  # POC settings for repeatable destroy
  ##########################################

  deletion_protection = false
  skip_final_snapshot = true


  ##########################################
  # Other Security Settings
  ##########################################

  copy_tags_to_snapshot = true

  tags = {
    Name = "peter-poc-mysql"
    Tier = "Database"
  }
}


############################################
# Outputs
############################################

output "db_instance_id" {
  description = "RDS MySQL instance ID"
  value       = aws_db_instance.mysql.id
}

output "db_endpoint" {
  description = "RDS MySQL endpoint"
  value       = aws_db_instance.mysql.address
}

output "db_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.mysql.port
}

output "db_name" {
  description = "RDS MySQL database name"
  value       = aws_db_instance.mysql.db_name
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN containing the RDS master credentials"

  value = try(
    aws_db_instance.mysql.master_user_secret[0].secret_arn,
    null
  )

  sensitive = true
}
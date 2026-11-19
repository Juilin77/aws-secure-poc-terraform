resource "aws_backup_vault" "ec2" {
  name = "backupvault-peter-vpc1-ec2-01"

  tags = {
    Name = "backupvault-peter-vpc1-ec2-01"
  }
}

resource "aws_backup_plan" "ec2_daily" {
  name = "backupplan-peter-vpc1-ec2-daily-01"

  rule {
    rule_name         = "daily-ec2-backup"
    target_vault_name = aws_backup_vault.ec2.name

    # 18:00 UTC = 02:00 Singapore time
    schedule = "cron(0 18 * * ? *)"

    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = 7
    }
  }
}

resource "aws_iam_role" "backup" {
  name = "iamrole-peter-vpc1-backup-01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "iamrole-peter-vpc1-backup-01"
  }
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_selection" "ec2" {
  name         = "backupsel-peter-vpc1-all-ec2-01"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.ec2_daily.id

  resources = [
    aws_instance.web.arn,
    aws_instance.app.arn,
    aws_instance.ad.arn,
    aws_instance.wsus.arn,
    aws_instance.repo.arn,
    aws_instance.reverse_proxy.arn,
    aws_instance.forward_proxy.arn,
    aws_instance.nat.arn
  ]
}
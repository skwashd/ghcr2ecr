data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

resource "random_password" "webhook_secret" {
  length  = 32
  special = true
}

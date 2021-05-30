resource "aws_ssm_parameter" "github_token" {
  name        = "/codebuild/${local.project_name}/GITHUB_TOKEN"
  description = "Token to read GitHub Container Registry images."
  type        = "SecureString"
  value       = var.github_token
  key_id      = data.aws_kms_alias.ssm.arn
  tags        = var.tags
}

data "aws_iam_policy_document" "codebuild" {

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullPushImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:CreateRepository",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }

  statement {
    sid     = "ReadParams"
    actions = ["ssm:GetParameters"]
    resources = [
      aws_ssm_parameter.github_token.arn
    ]
  }

  statement {
    sid = "DecryptParams"
    actions = [
      "kms:Decrypt"
    ]
    resources = [data.aws_kms_alias.ssm.arn]
  }

  statement {
    sid       = "DescribeLogs"
    actions   = ["logs:DescribeLogStreams"]
    resources = ["${join(":", slice(split(":", aws_cloudwatch_log_group.codebuild.arn), 0, 5))}:*"]
  }

  statement {
    sid       = "StreamLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
  }
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    sid     = "AssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.project_name}CodeBuildRun"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "codebuild" {
  role   = aws_iam_role.codebuild.name
  policy = data.aws_iam_policy_document.codebuild.json
}

data "template_file" "buildspec" {
  template = file("${path.module}/buildspec.yml.tpl")
  vars = {
    aws_account_id      = data.aws_caller_identity.current.account_id,
    aws_region          = var.aws_region,
    github_org          = var.github_org
    build_script_url    = var.build_script_url
    build_script_sha256 = var.build_script_sha256
    project_name        = local.project_name
  }
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.project_name}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_codebuild_project" "sync_image" {
  name          = local.project_name
  build_timeout = var.build_timeout
  service_role  = aws_iam_role.codebuild.arn


  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
    type                        = "LINUX_CONTAINER"
  }

  logs_config {
    cloudwatch_logs {
      group_name = element(split(":", aws_cloudwatch_log_group.codebuild.arn), 6)
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = data.template_file.buildspec.rendered
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  tags = var.tags
}

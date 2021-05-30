resource "aws_ssm_parameter" "webhook_secret" {
  name        = "/${local.project_name}/WEBHOOK_SECRET"
  description = "GitHub webhook secret for validating requests."
  type        = "SecureString"
  value       = jsonencode(random_password.webhook_secret.result)
  key_id      = data.aws_kms_alias.ssm.arn
  tags        = var.tags
}

resource "aws_apigatewayv2_api" "this" {
  name          = local.project_name
  description   = "GitHub webhook listener for changes in packages in the ${var.github_org} organisation."
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_lambda_permission" "this" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${local.project_name}"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode(
      {
        httpMethod     = "$context.httpMethod"
        ip             = "$context.identity.sourceIp"
        protocol       = "$context.protocol"
        requestId      = "$context.requestId"
        requestTime    = "$context.requestTime"
        responseLength = "$context.responseLength"
        routeKey       = "$context.routeKey"
        status         = "$context.status"
      }
    )
  }

  lifecycle {
    ignore_changes = [
      deployment_id,
      default_route_settings
    ]
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "this" {
  api_id           = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"

  integration_method   = "POST"
  integration_uri      = aws_lambda_function.this.invoke_arn
  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_apigatewayv2_route" "lambda-route" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /packages"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_lambda_function" "this" {
  function_name = local.project_name
  description   = "Processor for GitHub webhook that listens for changes in packages in the ${var.github_org} organisation."

  runtime     = "python3.8"
  handler     = "handler.handler"
  memory_size = 128
  timeout     = 30

  role = aws_iam_role.lambda.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.lambda]
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/python/"
  output_path = ".terraform/tmp/lambda/handler.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.project_name}"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_iam_role" "lambda" {
  name               = "lambda-${local.project_name}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  role   = aws_iam_role.lambda.name
  policy = data.aws_iam_policy_document.lambda.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "TriggerCodeBuild"
    actions   = ["codebuild:StartBuild"]
    resources = [aws_codebuild_project.sync_image.arn]
  }

  statement {
    sid = "DecryptParams"
    actions = [
      "kms:Decrypt"
    ]
    resources = [data.aws_kms_alias.ssm.arn]
  }

  statement {
    sid     = "ReadParams"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.webhook_secret.arn
    ]
  }

  statement {
    sid       = "DescribeLogs"
    actions   = ["logs:DescribeLogStreams"]
    resources = ["${join(":", slice(split(":", aws_cloudwatch_log_group.lambda.arn), 0, 5))}:*"]
  }

  statement {
    sid       = "StreamLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

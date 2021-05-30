output "api_gateway_url" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "api_gateway_arn" {
  value = aws_apigatewayv2_api.this.arn
}

output "lambda_arn" {
  value = aws_lambda_function.this.arn
}

output "codebuild_project_arn" {
  value = aws_codebuild_project.sync_image.arn
}

output "github_webhook_url" {
  value = github_organization_webhook.this.url
}

output "ssm_param_webhook_secret_arn" {
  value = aws_ssm_parameter.webhook_secret.arn
}

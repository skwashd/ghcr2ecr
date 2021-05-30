resource "github_organization_webhook" "this" {
  configuration {
    url          = "${aws_apigatewayv2_api.this.api_endpoint}/packages"
    content_type = "json"
    insecure_ssl = false
    secret       = random_password.webhook_secret.result
  }

  active = true

  events = ["package_v2"]
}

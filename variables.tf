variable "github_token" {
  description = "Token to read GitHub Container Registry images."
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "Name of GitHub organisation for the container registry."
  type        = string
}

variable "build_script_url" {
  description = "The URL of the gist to be run by CodeBuild."
  type        = string
  default     = "https://github.com/skwashd/ghcr2cr/raw/main/gist/sync.py"
}

variable "build_script_sha256" {
  description = "The SHA256 has of the CodeBuild script. This ensures integrity of the script."
  type        = string
  default     = "5c8623f32b563135e3debe006ff1405bff5104c57604cfe47614410458e6cfab"
}

variable "build_timeout" {
  description = "Build timeout in seconds."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

locals {
  project_name = "${var.github_org}SyncImages"
}

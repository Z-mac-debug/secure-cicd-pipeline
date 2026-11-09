variable "region" {
  description = "AWS region for the artefact bucket"
  type        = string
  default     = "eu-west-2"
}

variable "bucket_name" {
  description = "Globally unique name for the artefact bucket"
  type        = string
  default     = "secure-cicd-pipeline-artifacts-example"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket names must be 3-63 lowercase letters, numbers, dots or hyphens."
  }
}

variable "retention_days" {
  description = "Days to keep current artefact versions"
  type        = number
  default     = 30
}

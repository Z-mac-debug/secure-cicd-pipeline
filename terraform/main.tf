# Sample infrastructure for Checkov to scan: a hardened S3 bucket for build
# artefacts, encrypted with a customer-managed KMS key. It is never applied by
# the pipeline; it exists to show IaC scanning and documented risk acceptance.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "secure-cicd-pipeline"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms" {
  # In a KMS key policy, Resource "*" means "this key", so these generic IAM checks don't apply.
  #checkov:skip=CKV_AWS_109:Key policy scoped to this key; account root needs administration rights.
  #checkov:skip=CKV_AWS_111:Key policy scoped to this key; account root needs administration rights.
  #checkov:skip=CKV_AWS_356:Resource "*" in a key policy refers only to the key itself.
  statement {
    sid       = "AccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "artifacts" {
  description             = "Encrypts the build artefact bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "artifacts" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.artifacts.key_id
}

resource "aws_s3_bucket" "artifacts" {
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for short-lived CI artefacts.
  #checkov:skip=CKV2_AWS_62:No downstream consumers need S3 event notifications.
  #checkov:skip=CKV_AWS_18:Access logging would need a separate log bucket; out of scope for this demo.
  bucket = var.bucket_name
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.artifacts.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-artefacts"
    status = "Enabled"

    filter {}

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

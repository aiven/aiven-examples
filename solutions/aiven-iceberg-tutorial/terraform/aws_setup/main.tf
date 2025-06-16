provider "aws" {
  region = var.aws_region
}

# S3 Bucket
resource "aws_s3_bucket" "iceberg_bucket" {
  bucket = var.s3_bucket_name
}

# IAM Policy for S3 access
resource "aws_iam_policy" "snowflake_s3_access" {
  name        = "snowflake_s3_access"
  description = "Policy for Snowflake to access S3 bucket"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${aws_s3_bucket.iceberg_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.iceberg_bucket.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["*"]
          }
        }
      }
    ]
  })
}

# Trust policy for IAM role
locals {
  trust_policy = var.snowflake_iam_user_arn != null ? {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.snowflake_iam_user_arn
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  } : {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  }
}

# IAM Role for Snowflake
resource "aws_iam_role" "snowflake_s3_role" {
  name               = "snowflake_s3_role"
  description        = "Role for Snowflake to access S3 bucket"
  assume_role_policy = jsonencode(local.trust_policy)
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "snowflake_s3_access" {
  role       = aws_iam_role.snowflake_s3_role.name
  policy_arn = aws_iam_policy.snowflake_s3_access.arn
} 
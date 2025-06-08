variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Iceberg tables"
  type        = string
}

variable "external_id" {
  description = "External ID for Snowflake trust relationship"
  type        = string
}

variable "snowflake_iam_user_arn" {
  description = "IAM user ARN from Snowflake Open Catalog"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {
    Project     = "aiven-iceberg-tutorial"
    ManagedBy   = "terraform"
  }
} 
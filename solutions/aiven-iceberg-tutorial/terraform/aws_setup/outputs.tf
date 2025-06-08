output "s3_bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.iceberg_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.iceberg_bucket.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Snowflake"
  value       = aws_iam_role.snowflake_s3_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for Snowflake"
  value       = aws_iam_role.snowflake_s3_role.name
} 
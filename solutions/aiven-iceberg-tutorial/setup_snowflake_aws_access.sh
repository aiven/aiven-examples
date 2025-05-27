#!/bin/bash

# Configuration variables
export AWS_ACCOUNT_ID="YOUR_AWS_ACCOUNT_ID"
export EXTERNAL_ID="YOUR_EXTERNAL_ID"
export S3_BUCKET_NAME="YOUR_BUCKET_NAME"

# Function to create IAM policy
create_iam_policy() {
    echo "Setting up IAM policy for Snowflake S3 access..."
    aws iam create-policy \
        --policy-name snowflake_s3_access \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:PutObject",
                        "s3:GetObject",
                        "s3:GetObjectVersion",
                        "s3:DeleteObject",
                        "s3:DeleteObjectVersion"
                    ],
                    "Resource": "arn:aws:s3:::'"$S3_BUCKET_NAME"'/*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:ListBucket",
                        "s3:GetBucketLocation"
                    ],
                    "Resource": "arn:aws:s3:::'"$S3_BUCKET_NAME"'",
                    "Condition": {
                        "StringLike": {
                            "s3:prefix": ["*"]
                        }
                    }
                }
            ]
        }' || echo "Policy 'snowflake_s3_access' may already exist. Continuing..."
}

# Function to create IAM role
create_iam_role() {
    echo "Setting up IAM role for Snowflake..."
    aws iam create-role \
        --role-name snowflake_s3_role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": "arn:aws:iam::'"$AWS_ACCOUNT_ID"':root"
                    },
                    "Action": "sts:AssumeRole",
                    "Condition": {
                        "StringEquals": {
                            "sts:ExternalId": "'"$EXTERNAL_ID"'"
                        }
                    }
                }
            ]
        }' || echo "Role 'snowflake_s3_role' may already exist. Continuing..."
}

# Function to attach policy to role
attach_policy_to_role() {
    echo "Attaching policy to role..."
    aws iam attach-role-policy \
        --role-name snowflake_s3_role \
        --policy-arn arn:aws:iam::"$AWS_ACCOUNT_ID":policy/snowflake_s3_access || \
        echo "Policy attachment may have failed. Please check if role and policy exist."
}

# Main execution
echo "Starting AWS IAM setup for Snowflake integration..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if configuration variables are set
if [ "$AWS_ACCOUNT_ID" = "YOUR_AWS_ACCOUNT_ID" ] || \
   [ "$EXTERNAL_ID" = "YOUR_EXTERNAL_ID" ] || \
   [ "$S3_BUCKET_NAME" = "YOUR_BUCKET_NAME" ]; then
    echo "Error: Please set the configuration variables at the top of the script."
    exit 1
fi

# Execute the setup steps
create_iam_policy
create_iam_role
attach_policy_to_role

echo "Setup completed! Please verify the configuration in AWS Console." 
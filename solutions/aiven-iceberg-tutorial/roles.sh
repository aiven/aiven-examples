#!/bin/bash

# Environment variables
export AWS_ACCOUNT_ID="XXX"
export EXTERNAL_ID="ext_vol"
export BUCKET_NAME="XX"

# Step 1: Create the IAM Policy
echo "Creating IAM Policy 'snowflake_access'..."
aws iam create-policy \
    --policy-name snowflake_access \
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
                "Resource": "arn:aws:s3:::'"$BUCKET_NAME"'/*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ],
                "Resource": "arn:aws:s3:::'"$BUCKET_NAME"'",
                "Condition": {
                    "StringLike": {
                        "s3:prefix": [
                            "*"
                        ]
                    }
                }
            }
        ]
    }' || echo "Policy 'snowflake_access' may already exist. Skipping policy creation."

# Step 2: Check if the role already exists
echo "Checking if IAM Role 'snowflakes_role' exists..."
ROLE_EXISTS=$(aws iam get-role --role-name snowflakes_role --query "Role.RoleName" --output text 2>/dev/null)

if [ "$ROLE_EXISTS" == "snowflakes_role" ]; then
    echo "IAM Role 'snowflakes_role' already exists, skipping role creation."
else
    # Create the IAM Role (snowflakes_role)
    echo "Creating IAM Role 'snowflakes_role'..."
    aws iam create-role \
        --role-name snowflakes_role \
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
        }' && echo "IAM Role 'snowflakes_role' created successfully."
fi

# Step 3: Attach the Policy to the Role
echo "Attaching Policy 'snowflake_access' to Role 'snowflakes_role'..."
aws iam attach-role-policy \
    --role-name snowflakes_role \
    --policy-arn arn:aws:iam::"$AWS_ACCOUNT_ID":policy/snowflake_access && \
    echo "Policy 'snowflake_access' successfully attached to Role 'snowflakes_role'."

echo "IAM Role and Policy setup completed successfully!" 
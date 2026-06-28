#!/usr/bin/env bash
#
# setup-bedrock.sh — provision the IAM identity query-agent uses to call
# Amazon Bedrock (Claude) from Aiven Apps.
#
# Context:
#   - query-agent runs on Aiven Apps (eu-west-1), OUTSIDE AWS, so it cannot use
#     an instance role. It authenticates to Bedrock with long-lived IAM keys.
#   - Bedrock model access is auto-enabled on first invocation (the old
#     "Model access" console page is retired). No manual EULA step for Claude
#     here; first-time Anthropic users may be asked for use-case details once.
#   - Region eu-west-1 is co-located with Aiven Apps; the `eu.` inference
#     profile keeps inference in-EU.
#
# Run with an identity that can write IAM (iam:CreateUser/PutUserPolicy/
# CreateAccessKey). Idempotent except create-access-key (commented out — run it
# yourself so the secret never lands in shared logs).
set -euo pipefail

USER="query-agent-bedrock"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
MODEL_ID="eu.anthropic.claude-sonnet-4-6"
REGION="eu-west-1"

echo "Account: ${ACCOUNT}  Region: ${REGION}  Model: ${MODEL_ID}"

# 1) Dedicated user (ignore "already exists").
aws iam create-user --user-name "$USER" \
  --tags Key=project,Value=aiven-trino-mcp-federation Key=purpose,Value=bedrock-invoke \
  2>/dev/null || echo "user ${USER} already exists, continuing"

# 2) Scoped inline policy: Bedrock invoke on Anthropic models only.
aws iam put-user-policy --user-name "$USER" \
  --policy-name bedrock-invoke \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"InvokeAnthropicOnBedrock\",
      \"Effect\": \"Allow\",
      \"Action\": [
        \"bedrock:InvokeModel\",
        \"bedrock:InvokeModelWithResponseStream\",
        \"bedrock:Converse\",
        \"bedrock:ConverseStream\"
      ],
      \"Resource\": [
        \"arn:aws:bedrock:*:${ACCOUNT}:inference-profile/eu.anthropic.*\",
        \"arn:aws:bedrock:*::foundation-model/anthropic.*\"
      ]
    }]
  }"
echo "policy bedrock-invoke attached to ${USER}"

# 3) Access key — run yourself so the SecretAccessKey stays out of shared logs:
#
#   aws iam create-access-key --user-name query-agent-bedrock
#
# Then set these as query-agent env vars (Aiven Apps secrets / local .env):
#   AWS_ACCESS_KEY_ID=<AccessKeyId>
#   AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
#   AWS_REGION=eu-west-1
#   BEDROCK_MODEL_ID=eu.anthropic.claude-sonnet-4-6
#
# Verify the scoped key can invoke (run in your terminal):
#   AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=eu-west-1 \
#   aws bedrock-runtime converse --model-id "${MODEL_ID}" \
#     --messages '[{"role":"user","content":[{"text":"Reply with exactly: OK"}]}]' \
#     --inference-config '{"maxTokens":10}' \
#     --query 'output.message.content[0].text' --output text
echo "Next: create the access key yourself (see comment above)."

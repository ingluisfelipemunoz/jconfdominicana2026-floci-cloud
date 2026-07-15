#!/usr/bin/env bash
set -euo pipefail

# Catch-up for Module 1: S3 -> SQS -> Lambda -> DynamoDB.
# Idempotent: safe to re-run. Assumes `eval "$(floci env)"` has been run.

here="$(cd "$(dirname "$0")" && pwd)"
ACCOUNT="000000000000"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
QUEUE_NAME="order-events"
QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT}:${QUEUE_NAME}"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Cannot reach an AWS endpoint. Is Floci running, and did you run:" >&2
  echo '    floci start && eval "$(floci env)"' >&2
  exit 1
fi

echo "==> S3 bucket"
if aws s3api head-bucket --bucket orders >/dev/null 2>&1; then
  echo "    bucket exists"
else
  aws s3 mb s3://orders >/dev/null
fi

echo "==> SQS queue"
if aws sqs get-queue-url --queue-name "$QUEUE_NAME" >/dev/null 2>&1; then
  echo "    queue exists"
else
  aws sqs create-queue --queue-name "$QUEUE_NAME" >/dev/null
fi

echo "==> DynamoDB table"
if aws dynamodb describe-table --table-name orders >/dev/null 2>&1; then
  echo "    table exists"
else
  aws dynamodb create-table \
    --table-name orders \
    --attribute-definitions AttributeName=orderId,AttributeType=S \
    --key-schema AttributeName=orderId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
fi
aws dynamodb wait table-exists --table-name orders

echo "==> Lambda function"
if aws lambda get-function --function-name process-order >/dev/null 2>&1; then
  aws lambda update-function-code \
    --function-name process-order \
    --zip-file "fileb://${here}/lambda/process-order/function.zip" >/dev/null
  echo "    function exists, code updated"
else
  aws lambda create-function \
    --function-name process-order \
    --runtime python3.12 \
    --handler handler.handler \
    --role "arn:aws:iam::${ACCOUNT}:role/lambda" \
    --zip-file "fileb://${here}/lambda/process-order/function.zip" >/dev/null
fi

# Nothing downstream validates the mapping, so a swallowed failure here looks
# like a green setup and a pipeline that silently never fires.
echo "==> SQS -> Lambda event source mapping"
existing=$(aws lambda list-event-source-mappings \
  --function-name process-order \
  --event-source-arn "$QUEUE_ARN" \
  --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null || echo "None")

if [ -n "$existing" ] && [ "$existing" != "None" ]; then
  echo "    mapping exists ($existing)"
else
  aws lambda create-event-source-mapping \
    --function-name process-order \
    --event-source-arn "$QUEUE_ARN" >/dev/null
fi

QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --query QueueUrl --output text)

echo "==> Done. Send an order with:"
echo "    aws sqs send-message --queue-url ${QUEUE_URL} --message-body file://${here}/events/sample-order.json"
echo "    aws dynamodb scan --table-name orders"

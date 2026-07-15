#Requires -Version 5.1
# Catch-up for Module 1 (Windows): S3 -> SQS -> Lambda -> DynamoDB.
# Idempotent: safe to re-run. Assumes the Floci env is set in this session
# (run `. .\00-setup\floci-env.ps1` first).

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$ACCOUNT = "000000000000"
$REGION = if ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { "us-east-1" }
$QUEUE_NAME = "order-events"
$QUEUE_ARN = "arn:aws:sqs:${REGION}:${ACCOUNT}:${QUEUE_NAME}"
$ZIP = Join-Path $here "lambda\process-order\function.zip"

aws sts get-caller-identity *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Cannot reach an AWS endpoint. Is Floci running, and did you run:"
    Write-Host '    floci start; . .\00-setup\floci-env.ps1'
    exit 1
}

Write-Host "==> S3 bucket"
aws s3api head-bucket --bucket orders *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    bucket exists"
} else {
    aws s3 mb s3://orders | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

Write-Host "==> SQS queue"
aws sqs get-queue-url --queue-name $QUEUE_NAME *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    queue exists"
} else {
    aws sqs create-queue --queue-name $QUEUE_NAME | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

Write-Host "==> DynamoDB table"
aws dynamodb describe-table --table-name orders *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    table exists"
} else {
    aws dynamodb create-table `
        --table-name orders `
        --attribute-definitions AttributeName=orderId,AttributeType=S `
        --key-schema AttributeName=orderId,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
aws dynamodb wait table-exists --table-name orders

Write-Host "==> Lambda function"
aws lambda get-function --function-name process-order *> $null
if ($LASTEXITCODE -eq 0) {
    aws lambda update-function-code `
        --function-name process-order `
        --zip-file "fileb://$ZIP" | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Write-Host "    function exists, code updated"
} else {
    aws lambda create-function `
        --function-name process-order `
        --runtime python3.12 `
        --handler handler.handler `
        --role "arn:aws:iam::${ACCOUNT}:role/lambda" `
        --zip-file "fileb://$ZIP" | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# Nothing downstream validates the mapping, so a swallowed failure here looks
# like a green setup and a pipeline that silently never fires.
Write-Host "==> SQS -> Lambda event source mapping"
$existing = aws lambda list-event-source-mappings `
    --function-name process-order `
    --event-source-arn $QUEUE_ARN `
    --query 'EventSourceMappings[0].UUID' --output text 2>$null
if ($LASTEXITCODE -ne 0) { $existing = "None" }

if ($existing -and $existing -ne "None") {
    Write-Host "    mapping exists ($existing)"
} else {
    aws lambda create-event-source-mapping `
        --function-name process-order `
        --event-source-arn $QUEUE_ARN | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

$QUEUE_URL = aws sqs get-queue-url --queue-name $QUEUE_NAME --query QueueUrl --output text

Write-Host "==> Done. Send an order with:"
Write-Host "    aws sqs send-message --queue-url $QUEUE_URL --message-body file://$here\events\sample-order.json"
Write-Host "    aws dynamodb scan --table-name orders"

#!/usr/bin/env bash
set -euo pipefail

# Azure taste. Same philosophy as the AWS edge, different family member.
# Pulls floci/floci-az:latest (covered by preflight).

echo "==> Starting Floci Azure"
floci az start
eval "$(floci az env)"   # exports AZURE_STORAGE_CONNECTION_STRING

echo "==> Create a blob container"
az storage container create --name my-container

echo "==> List containers"
az storage container list --output table

echo "==> Done. Stop with: floci az stop --remove"

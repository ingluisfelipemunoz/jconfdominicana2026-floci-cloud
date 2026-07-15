#!/usr/bin/env bash
# Sample init script, mounted at /etc/localstack/init/ready.d/.
# This file is byte-for-byte identical on the Floci side: it runs unchanged,
# which is the whole point of the migration module.
set -euo pipefail

awslocal s3 mb s3://migrated-bucket || aws s3 mb s3://migrated-bucket
echo "init script ran"

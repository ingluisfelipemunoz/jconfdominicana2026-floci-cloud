#Requires -Version 5.1
# Final demo (Windows): a GitHub Actions workflow, run locally with `act`, doing
# a full S3 round-trip against Floci. CI locally + cloud locally, no account
# anywhere.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$IMAGE = "catthehacker/ubuntu:act-latest"

# act talks to the Docker daemon directly. Point it at the active context's
# endpoint (Docker Desktop on Windows exposes a named pipe).
if (-not $env:DOCKER_HOST) {
    $dh = docker context inspect --format '{{.Endpoints.docker.Host}}' 2>$null
    if ($dh) { $env:DOCKER_HOST = $dh }
}

# Floci is started by the workflow as a service container — nothing to start here.

$archFlag = @()
if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    # catthehacker runner images are amd64; emulate on ARM machines.
    $archFlag = @("--container-architecture", "linux/amd64")
}

Write-Host "==> Pre-pulling the act runner image (once; fast if cached)"
docker pull --platform linux/amd64 $IMAGE | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Running the workflow with act"
Push-Location $here
act push -P "ubuntu-latest=$IMAGE" --pull=false @archFlag
$ok = $LASTEXITCODE
Pop-Location
exit $ok

#Requires -Version 5.1
# Preflight for "Build a Whole Cloud Locally with Floci" (Windows).
# Run this at home on good wifi BEFORE the workshop.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Checking Docker"
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker is not running. Start Docker Desktop."
    exit 1
}

Write-Host "==> Checking the AWS CLI"
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Error "The AWS CLI (v2) is not installed. See https://aws.amazon.com/cli/"
    exit 1
}

# Modules 1, 2 and 3 all build a Quarkus app. Without these the workshop stops
# dead, so fail here at home rather than in the room.
Write-Host "==> Checking Java 21+ and Maven"
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Error "Java is not installed. The workshop needs Java 21 or newer."
    exit 1
}
$javaVersionLine = (java -version 2>&1 | Select-Object -First 1)
if ($javaVersionLine -match 'version "(\d+)') {
    $javaMajor = [int]$Matches[1]
    if ($javaMajor -lt 21) {
        Write-Error "Java $javaMajor is too old. The workshop needs Java 21 or newer."
        exit 1
    }
    Write-Host "    Java $javaMajor"
} else {
    Write-Host "    NOTE: could not parse the Java version. Make sure 'java -version' reports 21 or newer."
}
if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
    Write-Error "Maven is not installed. See https://maven.apache.org/install.html"
    exit 1
}

# Needed only for the Module 3 EKS half and the Module 5 capstone. Warn rather
# than fail, so someone missing them can still do most of the workshop.
foreach ($tool in @("kubectl", "act")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "    NOTE: '$tool' is not installed. You'll need it later (kubectl for EKS, act for the capstone)."
    }
}

Write-Host "==> Installing the Floci CLI (skips if present)"
if (-not (Get-Command floci -ErrorAction SilentlyContinue)) {
    Invoke-RestMethod https://floci.io/install.ps1 | Invoke-Expression
    # The installer edits the persisted PATH, which this session has already
    # read. Pull it back in so the smoke test below can find the binary.
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command floci -ErrorAction SilentlyContinue)) {
        Write-Error "Installed the Floci CLI, but 'floci' is not on your PATH. Open a new terminal and re-run this script."
        exit 1
    }
}

Write-Host "==> Pulling images (this is the slow part, do it on good wifi)"
Get-Content (Join-Path $here "images.txt") | ForEach-Object {
    $image = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($image)) { return }
    if ($image.StartsWith("#")) { return }
    Write-Host "    pulling $image"
    docker pull $image
}

# Cold Quarkus/Maven dependency resolution is the single slowest thing in the
# workshop, and it is pure download. Do it here, on good wifi, so Modules 1 and 3
# build from a warm cache in seconds instead of stalling the room.
Write-Host "==> Warming the Maven cache (building the two Quarkus apps)"
foreach ($app in @("01-events-core\order-cli", "03-real-infra\order-api")) {
    $path = Join-Path (Split-Path -Parent $here) $app
    Write-Host "    building $(Split-Path -Leaf $path)"
    Push-Location $path
    mvn -q package
    $ok = $LASTEXITCODE
    Pop-Location
    if ($ok -ne 0) {
        Write-Error "Could not build $(Split-Path -Leaf $path). Fix this before the workshop."
        exit 1
    }
}

Write-Host "==> Smoke test"
floci start

# `floci env` emits shell syntax (`export KEY=value`), which PowerShell cannot
# evaluate. Parse the assignments out instead of piping them to Invoke-Expression.
foreach ($line in (floci env)) {
    if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        $name  = $Matches[1]
        $value = $Matches[2].Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$name" -Value $value
    }
}

aws s3 mb s3://preflight-check
aws s3 ls
floci stop --remove

Write-Host "==> All good. See you at the workshop."

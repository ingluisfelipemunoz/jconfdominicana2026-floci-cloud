#Requires -Version 5.1
# Azure taste (Windows). Same philosophy as the AWS edge, different family member.
# Pulls floci/floci-az:latest (covered by preflight).

$ErrorActionPreference = "Stop"

Write-Host "==> Starting Floci Azure"
floci az start
if ($LASTEXITCODE -ne 0) { exit 1 }

# The PowerShell twin of:  eval "$(floci az env)"
# Exports AZURE_STORAGE_CONNECTION_STRING into this session.
foreach ($line in (floci az env)) {
    if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        $name  = $Matches[1]
        $value = $Matches[2].Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$name" -Value $value
    }
}

Write-Host "==> Create a blob container"
az storage container create --name my-container
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> List containers"
az storage container list --output table
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Done. Stop with: floci az stop --remove"

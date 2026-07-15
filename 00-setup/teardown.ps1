#Requires -Version 5.1
# Give your laptop back (Windows). Removes everything the workshop created.
#
#   .\00-setup\teardown.ps1            containers, volumes, kubeconfig contexts
#   .\00-setup\teardown.ps1 -Images    the above, PLUS the ~8 GB of pulled images
#
# Safe to run at any point, and safe to re-run. It only touches things this
# workshop made: `floci*` containers/volumes, the order-api image, and the EKS
# kubeconfig contexts. Nothing else on your Docker is touched.

param([switch]$Images)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

Write-Host "==> Stopping Floci"
floci stop --remove *> $null
floci az stop --remove *> $null

# Floci spawns real engine containers (Lambda, ECS tasks, k3s, the ECR registry).
# Stopping the edge does not remove them, so sweep them up by name.
Write-Host "==> Removing engine containers Floci spawned"
$containers = docker ps -a --format '{{.Names}}' 2>$null | Where-Object { $_ -match '^floci' }
if ($containers) {
    $containers | ForEach-Object { Write-Host "    $_" }
    $containers | ForEach-Object { docker rm -f $_ *> $null }
} else {
    Write-Host "    none"
}

# The migration module's compose stack, if it's still up.
docker compose -f (Join-Path $root "04-migrate-multicloud\floci-after\compose.yaml") down -v *> $null

# k3s keeps its whole state (including its node registry) in a NAMED volume that
# survives `docker rm`. Leave it and the next cluster you create comes up with a
# stale second node whose pods hang forever. This is the step people miss.
Write-Host "==> Removing state volumes"
$volumes = docker volume ls -q 2>$null | Where-Object { $_ -match '^floci-(eks|ecr)' }
if ($volumes) {
    $volumes | ForEach-Object { Write-Host "    $_" }
    $volumes | ForEach-Object { docker volume rm $_ *> $null }
} else {
    Write-Host "    none"
}

Write-Host "==> Removing the order-api image you built"
docker rmi -f order-api:1.0 *> $null
if ($LASTEXITCODE -eq 0) { Write-Host "    removed" } else { Write-Host "    not present" }

Write-Host "==> Removing the EKS kubeconfig contexts"
$contexts = kubectl config get-contexts -o name 2>$null | Where-Object { $_ -match 'cluster/demo' }
foreach ($ctx in $contexts) {
    kubectl config delete-context $ctx *> $null
    kubectl config delete-cluster $ctx *> $null
    Write-Host "    $ctx"
}

if ($Images) {
    Write-Host "==> Removing the pulled images (~8 GB)"
    Get-Content (Join-Path $here "images.txt") | ForEach-Object {
        $image = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($image)) { return }
        if ($image.StartsWith("#")) { return }
        docker rmi -f $image *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "    removed $image" }
    }
} else {
    Write-Host "==> Keeping the pulled images (re-run with -Images to remove ~8 GB too)"
}

Write-Host "==> Done. Your laptop is your own again."

#Requires -Version 5.1
# GCP taste (Windows). Same philosophy again, third family member.
# Pulls floci/floci-gcp:latest (covered by preflight).
#
# WHY the raw JSON API AND NOT gcloud (verified 2026-07-14 against gcloud 573.0.0):
# The modern `gcloud storage` surface does NOT honor STORAGE_EMULATOR_HOST, and
# neither does the `gsutil` that ships alongside it. Both ignore the emulator, go
# straight to real Google, and fail — `401: Login Required` from gcloud, and
# `401 Anonymous caller does not have storage.buckets.list access` from gsutil.
# That is a gcloud problem, not a Floci one.
#
# The emulator itself is healthy and speaks the real GCS JSON API, so we drive it
# the way an SDK would. Any Google client library that DOES respect
# STORAGE_EMULATOR_HOST (the Python, Java and Go ones do) works against it too —
# which is the point worth making on stage.

$ErrorActionPreference = "Stop"

$PROJECT = "floci-local"
$PORT = 4588
$API = "http://localhost:$PORT/storage/v1"

Write-Host "==> Starting Floci GCP"
docker rm -f floci-gcp *> $null
docker run --rm -d --name floci-gcp -p "${PORT}:${PORT}" floci/floci-gcp:latest | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Waiting for it to be ready"
$ready = $false
foreach ($i in 1..30) {
    try {
        Invoke-WebRequest -Uri "$API/b?project=$PROJECT" -UseBasicParsing -TimeoutSec 2 | Out-Null
        $ready = $true
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}
if (-not $ready) {
    Write-Host "Floci GCP did not become ready on port $PORT."
    exit 1
}

Write-Host "==> Create a bucket"
Invoke-RestMethod -Method Post -Uri "$API/b?project=$PROJECT" `
    -ContentType "application/json" `
    -Body '{"name":"my-bucket"}' | Out-Null
Write-Host "    created gs://my-bucket"

Write-Host "==> Upload an object"
Invoke-RestMethod -Method Post `
    -Uri "http://localhost:$PORT/upload/storage/v1/b/my-bucket/o?uploadType=media&name=hello.txt" `
    -ContentType "text/plain" `
    -Body "Hello from Floci GCP" | Out-Null
Write-Host "    uploaded hello.txt"

Write-Host "==> List buckets"
$buckets = Invoke-RestMethod -Uri "$API/b?project=$PROJECT"
$buckets.items | ForEach-Object { Write-Host "    $($_.name)" }

Write-Host "==> Read the object back"
$body = Invoke-RestMethod -Uri "$API/b/my-bucket/o/hello.txt?alt=media"
Write-Host "    $body"

Write-Host "==> Done. Stop with: docker rm -f floci-gcp"

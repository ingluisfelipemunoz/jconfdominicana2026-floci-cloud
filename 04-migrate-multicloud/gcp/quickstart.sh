#!/usr/bin/env bash
set -euo pipefail

# GCP taste. Same philosophy again, third family member.
# Pulls floci/floci-gcp:latest (covered by preflight).
#
# WHY curl AND NOT gcloud (verified 2026-07-14 against gcloud 573.0.0):
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

PROJECT="floci-local"
PORT=4588
API="http://localhost:${PORT}/storage/v1"

echo "==> Starting Floci GCP"
docker rm -f floci-gcp >/dev/null 2>&1 || true
docker run --rm -d --name floci-gcp -p "${PORT}:${PORT}" floci/floci-gcp:latest >/dev/null

echo "==> Waiting for it to be ready"
ready=""
for _ in $(seq 1 30); do
  if curl -sf -m 2 "${API}/b?project=${PROJECT}" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ -n "$ready" ] || { echo "Floci GCP did not become ready on port ${PORT}." >&2; exit 1; }

echo "==> Create a bucket"
curl -sf -X POST "${API}/b?project=${PROJECT}" \
  -H 'Content-Type: application/json' \
  -d '{"name":"my-bucket"}' >/dev/null
echo "    created gs://my-bucket"

echo "==> Upload an object"
curl -sf -X POST "http://localhost:${PORT}/upload/storage/v1/b/my-bucket/o?uploadType=media&name=hello.txt" \
  -H 'Content-Type: text/plain' \
  --data-binary "Hello from Floci GCP" >/dev/null
echo "    uploaded hello.txt"

echo "==> List buckets"
curl -sf "${API}/b?project=${PROJECT}" | grep -o '"name":"[^"]*"' | sed 's/^/    /'

echo "==> Read the object back"
printf '    '
curl -sf "${API}/b/my-bucket/o/hello.txt?alt=media"
echo

echo "==> Done. Stop with: docker rm -f floci-gcp"

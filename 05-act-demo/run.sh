#!/usr/bin/env bash
set -euo pipefail

# Final demo: a GitHub Actions workflow, run locally with `act`, doing a full
# S3 round-trip against Floci. CI locally + cloud locally, no account anywhere.

here="$(cd "$(dirname "$0")" && pwd)"
IMAGE="catthehacker/ubuntu:act-latest"

# act talks to the Docker daemon directly. Docker Desktop on macOS puts the
# socket under ~/.docker/run, not /var/run — point act at the active one.
if [ -z "${DOCKER_HOST:-}" ]; then
  DH="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
  [ -n "$DH" ] && export DOCKER_HOST="$DH"
fi

# Floci is started by the workflow as a service container — nothing to start here.

ARCH_FLAG=()
case "$(uname -m)" in
  arm64|aarch64)
    # catthehacker runner images are amd64; emulate on Apple Silicon.
    ARCH_FLAG=(--container-architecture linux/amd64) ;;
esac

echo "==> Pre-pulling the act runner image (once; fast if cached)"
docker pull --platform linux/amd64 "$IMAGE" >/dev/null

echo "==> Running the workflow with act"
cd "$here"
act push -P "ubuntu-latest=$IMAGE" --pull=false "${ARCH_FLAG[@]}"

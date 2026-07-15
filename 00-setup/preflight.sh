#!/usr/bin/env bash
set -euo pipefail

# Preflight for "Build a Whole Cloud Locally with Floci".
# Run this at home on good wifi BEFORE the workshop.

here="$(cd "$(dirname "$0")" && pwd)"

echo "==> Checking Docker"
docker info >/dev/null 2>&1 || {
  echo "Docker is not running. Start Docker Desktop or the daemon." >&2
  exit 1
}

echo "==> Checking the AWS CLI"
command -v aws >/dev/null 2>&1 || {
  echo "The AWS CLI (v2) is not installed. See https://aws.amazon.com/cli/" >&2
  exit 1
}

# Modules 1, 2 and 3 all build a Quarkus app. Without these the workshop stops
# dead, so fail here at home rather than in the room.
echo "==> Checking Java 21+ and Maven"
command -v java >/dev/null 2>&1 || {
  echo "Java is not installed. The workshop needs Java 21 or newer." >&2
  exit 1
}
java_major="$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')"
case "$java_major" in
  ''|*[!0-9]*)
    echo "Could not parse the Java version. Make sure 'java -version' reports 21 or newer." >&2 ;;
  *)
    if [ "$java_major" -lt 21 ]; then
      echo "Java $java_major is too old. The workshop needs Java 21 or newer." >&2
      exit 1
    fi
    echo "    Java $java_major" ;;
esac
command -v mvn >/dev/null 2>&1 || {
  echo "Maven is not installed. See https://maven.apache.org/install.html" >&2
  exit 1
}

# Needed only for the Module 3 EKS half and the Module 5 capstone. Warn rather
# than fail, so someone missing them can still do most of the workshop.
for tool in kubectl act; do
  command -v "$tool" >/dev/null 2>&1 || \
    echo "    NOTE: '$tool' is not installed. You'll need it later (kubectl for EKS, act for the capstone)."
done

echo "==> Installing the Floci CLI (skips if present)"
if ! command -v floci >/dev/null 2>&1; then
  curl -fsSL https://floci.io/install.sh | sh
  # The installer drops the binary into a directory this shell may not have
  # looked in yet, so refresh the lookup cache before calling it below.
  hash -r
  command -v floci >/dev/null 2>&1 || {
    echo "Installed the Floci CLI, but 'floci' is not on your PATH." >&2
    echo "Open a new terminal and re-run this script." >&2
    exit 1
  }
fi

echo "==> Pulling images (this is the slow part, do it on good wifi)"
while read -r image; do
  [ -z "$image" ] && continue
  case "$image" in \#*) continue ;; esac
  echo "    pulling $image"
  docker pull "$image"
done < "$here/images.txt"

# Cold Quarkus/Maven dependency resolution is the single slowest thing in the
# workshop, and it is pure download. Do it here, on good wifi, so Modules 1 and 3
# build from a warm cache in seconds instead of stalling the room.
echo "==> Warming the Maven cache (building the two Quarkus apps)"
for app in "$here/../01-events-core/order-cli" "$here/../03-real-infra/order-api"; do
  echo "    building $(basename "$app")"
  (cd "$app" && mvn -q package) || {
    echo "Could not build $(basename "$app"). Fix this before the workshop." >&2
    exit 1
  }
done

echo "==> Smoke test"
floci start
eval "$(floci env)"
aws s3 mb s3://preflight-check
aws s3 ls
floci stop --remove

echo "==> All good. See you at the workshop."

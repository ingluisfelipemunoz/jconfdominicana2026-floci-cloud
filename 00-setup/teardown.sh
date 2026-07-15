#!/usr/bin/env bash
set -uo pipefail

# Give your laptop back. Removes everything the workshop created.
#
#   ./00-setup/teardown.sh            containers, volumes, kubeconfig contexts
#   ./00-setup/teardown.sh --images   the above, PLUS the ~8 GB of pulled images
#
# Safe to run at any point, and safe to re-run. It only touches things this
# workshop made: `floci*` containers/volumes, the order-api image, and the EKS
# kubeconfig contexts. Nothing else on your Docker is touched.

WITH_IMAGES=""
[ "${1:-}" = "--images" ] && WITH_IMAGES=1

echo "==> Stopping Floci"
floci stop --remove >/dev/null 2>&1 || true
floci az stop --remove >/dev/null 2>&1 || true

# Floci spawns real engine containers (Lambda, ECS tasks, k3s, the ECR registry).
# Stopping the edge does not remove them, so sweep them up by name.
echo "==> Removing engine containers Floci spawned"
CONTAINERS=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^floci' || true)
if [ -n "$CONTAINERS" ]; then
  echo "$CONTAINERS" | sed 's/^/    /'
  echo "$CONTAINERS" | xargs docker rm -f >/dev/null 2>&1 || true
else
  echo "    none"
fi

# The migration module's compose stack, if it's still up.
docker compose -f "$(dirname "$0")/../04-migrate-multicloud/floci-after/compose.yaml" down -v >/dev/null 2>&1 || true

# k3s keeps its whole state (including its node registry) in a NAMED volume that
# survives `docker rm`. Leave it and the next cluster you create comes up with a
# stale second node whose pods hang forever. This is the step people miss.
echo "==> Removing state volumes"
VOLUMES=$(docker volume ls -q 2>/dev/null | grep -E '^floci-(eks|ecr)' || true)
if [ -n "$VOLUMES" ]; then
  echo "$VOLUMES" | sed 's/^/    /'
  echo "$VOLUMES" | xargs docker volume rm >/dev/null 2>&1 || true
else
  echo "    none"
fi

echo "==> Removing the order-api image you built"
docker rmi -f order-api:1.0 >/dev/null 2>&1 && echo "    removed" || echo "    not present"

echo "==> Removing the EKS kubeconfig contexts"
for ctx in $(kubectl config get-contexts -o name 2>/dev/null | grep 'cluster/demo' || true); do
  kubectl config delete-context "$ctx" >/dev/null 2>&1 || true
  kubectl config delete-cluster "$ctx" >/dev/null 2>&1 || true
  echo "    $ctx"
done

if [ -n "$WITH_IMAGES" ]; then
  echo "==> Removing the pulled images (~8 GB)"
  while read -r image; do
    [ -z "$image" ] && continue
    case "$image" in \#*) continue ;; esac
    docker rmi -f "$image" >/dev/null 2>&1 && echo "    removed $image"
  done < "$(dirname "$0")/images.txt"
else
  echo "==> Keeping the pulled images (re-run with --images to remove ~8 GB too)"
fi

echo "==> Done. Your laptop is your own again."

#!/usr/bin/env bash
set -euo pipefail

# Catch-up for the finale: the Quarkus order-api running as a real ECS container,
# plus a real Kubernetes cluster (EKS, backed by k3s).
#
# Idempotent: safe to re-run. Assumes `floci start` is up and
# `eval "$(floci env)"` has been run.
#
# The API serves the orders Module 1 produced, so this script bootstraps Module 1
# state if it is missing. Fall behind anywhere and this one script catches you up.
#
# Resource note: ECS and EKS together are fine on most laptops; on 8 GB machines
# run them one at a time (comment out the EKS block).

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

ACCOUNT="000000000000"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# --- ECS ---
ECS_CLUSTER="workshop"
FAMILY="order-api"
IMAGE="order-api:1.0"
CONTAINER_PORT=8080
# 8080 is a popular port (floci-ui, anyone's dev server), so publish on 8081.
# Override if that one is taken too:  ORDER_API_PORT=9090 ./03-real-infra/setup.sh
HOST_PORT="${ORDER_API_PORT:-8081}"

# The endpoint the TASK CONTAINER uses to call back into the Floci edge on the
# host. Floci 1.5.31 does not inject AWS_* into ECS task containers (Lambda gets
# it, ECS does not), so we pass it explicitly in the task definition.
# Docker Desktop (macOS/Windows) resolves host.docker.internal natively.
# On Linux, if this does not resolve inside the task, use the bridge gateway:
#     ORDERS_API_ENDPOINT=http://172.17.0.1:4566 ./03-real-infra/setup.sh
TASK_ENDPOINT="${ORDERS_API_ENDPOINT:-http://host.docker.internal:4566}"

# --- EKS ---
EKS_CLUSTER="demo"
EKS_TIMEOUT_SECONDS=300

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Cannot reach an AWS endpoint. Is Floci running, and did you run:" >&2
  echo '    floci start && eval "$(floci env)"' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 0. Module 1 state. The API has nothing to serve without it.
# ---------------------------------------------------------------------------
echo "==> Module 1 pipeline (the data the API serves)"
if aws dynamodb describe-table --table-name orders >/dev/null 2>&1; then
  echo "    orders table exists"
else
  echo "    orders table missing, running ./01-events-core/setup.sh"
  "$root/01-events-core/setup.sh" >/dev/null
fi

# An empty table makes for a dull demo. Seed one order through the real Module 1
# pipeline (SQS -> Lambda -> DynamoDB) rather than writing to DynamoDB directly,
# so what the API serves genuinely came out the far end of the pipeline.
COUNT=$(aws dynamodb scan --table-name orders --query Count --output text 2>/dev/null || echo 0)
if [ "$COUNT" = "0" ]; then
  echo "    table is empty, sending a sample order through SQS -> Lambda"
  QUEUE_URL=$(aws sqs get-queue-url --queue-name order-events --query QueueUrl --output text)
  aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "file://${root}/01-events-core/events/sample-order.json" >/dev/null

  for _ in $(seq 1 30); do
    COUNT=$(aws dynamodb scan --table-name orders --query Count --output text 2>/dev/null || echo 0)
    [ "$COUNT" != "0" ] && break
    sleep 2
  done
  if [ "$COUNT" = "0" ]; then
    echo "    the Lambda has not written the order yet; the API will start empty." >&2
    echo "    Check it with:  docker ps | grep lambda" >&2
  fi
fi
echo "    ${COUNT} order(s) in DynamoDB"

# Anyone who fell behind and ran only THIS script has no order-cli jar, and the
# closing message below tells them to run it. Build it if it's missing.
CLI_JAR="$root/01-events-core/order-cli/target/quarkus-app/quarkus-run.jar"
if [ ! -f "$CLI_JAR" ]; then
  echo "    building the Module 1 CLI (you'll want it at the end of this module)"
  (cd "$root/01-events-core/order-cli" && mvn -q package)
fi

# ---------------------------------------------------------------------------
# 1. Build the app and bake it into a local image.
# ---------------------------------------------------------------------------
# No ECR, no docker push, no registry login. Floci's ECS resolves the image from
# the local Docker daemon and only pulls when it is absent, so a plain local tag
# is all a task definition needs.
echo "==> Building order-api (Quarkus)"
(cd "$here/order-api" && mvn -q package)

echo "==> Building the container image ${IMAGE}"
docker build -q -t "$IMAGE" "$here/order-api" >/dev/null
echo "    built ${IMAGE}"

# ---------------------------------------------------------------------------
# 2. ECS: cluster, task definition, task.
# ---------------------------------------------------------------------------
echo "==> ECS: cluster"
STATUS=$(aws ecs describe-clusters --clusters "$ECS_CLUSTER" \
  --query 'clusters[0].status' --output text 2>/dev/null || echo "None")
if [ "$STATUS" = "ACTIVE" ]; then
  echo "    cluster ${ECS_CLUSTER} exists"
else
  aws ecs create-cluster --cluster-name "$ECS_CLUSTER" >/dev/null
  echo "    created cluster ${ECS_CLUSTER}"
fi

# Two load-bearing choices here, both easy to get wrong:
#
#   network-mode bridge  — awsvpc DISCARDS the literal hostPort and hands you a
#                          random one instead, so the URL we print below would be
#                          wrong. Do not switch this to awsvpc.
#   an explicit hostPort — a hostPort of 0 (or absent) also means a random port.
#
# For the same reason we do NOT pass --requires-compatibilities FARGATE: it
# forces awsvpc. (--launch-type FARGATE on run-task is fine and does not.)
echo "==> ECS: task definition"
REVISION=$(aws ecs register-task-definition \
  --family "$FAMILY" \
  --network-mode bridge \
  --container-definitions "[{
    \"name\": \"app\",
    \"image\": \"${IMAGE}\",
    \"essential\": true,
    \"memory\": 1024,
    \"portMappings\": [{\"containerPort\": ${CONTAINER_PORT}, \"hostPort\": ${HOST_PORT}, \"protocol\": \"tcp\"}],
    \"environment\": [
      {\"name\": \"AWS_ENDPOINT_URL\",      \"value\": \"${TASK_ENDPOINT}\"},
      {\"name\": \"AWS_REGION\",            \"value\": \"${REGION}\"},
      {\"name\": \"AWS_ACCESS_KEY_ID\",     \"value\": \"test\"},
      {\"name\": \"AWS_SECRET_ACCESS_KEY\", \"value\": \"test\"},
      {\"name\": \"ORDERS_TABLE\",          \"value\": \"orders\"}
    ]
  }]" \
  --query 'taskDefinition.revision' --output text)
echo "    registered ${FAMILY}:${REVISION}"

# run-task always launches a NEW task, so re-running this unguarded would pile up
# containers fighting over host port ${HOST_PORT}. Stop what is running first;
# that also guarantees the task picks up the image we just rebuilt instead of
# leaving a stale one serving.
echo "==> ECS: stopping any previous order-api task"
RUNNING=$(aws ecs list-tasks --cluster "$ECS_CLUSTER" --desired-status RUNNING \
  --query 'taskArns' --output text 2>/dev/null || true)
for arn in $RUNNING; do
  [ "$arn" = "None" ] && continue
  aws ecs stop-task --cluster "$ECS_CLUSTER" --task "$arn" >/dev/null 2>&1 || true
  echo "    stopped ${arn##*/}"
done

# Give Docker a moment to actually release the host port.
for _ in $(seq 1 15); do
  docker ps --filter "name=floci-ecs-" --format '{{.Names}}' | grep -q . || break
  sleep 1
done

# Floci's default storage is in-memory, so restarting it makes Floci FORGET its
# tasks — while the task containers keep running, and keep holding host port
# ${HOST_PORT}. `stop-task` above can't help: there is no task to stop any more.
# The new container then fails to bind the port and the whole module dies in a
# confusing way. Reap the orphans directly.
ORPHANS=$(docker ps --filter "name=floci-ecs-" --format '{{.Names}}' 2>/dev/null || true)
for c in $ORPHANS; do
  echo "    removing orphaned container ${c} (Floci restarted and lost track of it)"
  docker rm -f "$c" >/dev/null 2>&1 || true
done

echo "==> ECS: running the task"
TASK_ARN=$(aws ecs run-task \
  --cluster "$ECS_CLUSTER" \
  --task-definition "${FAMILY}:${REVISION}" \
  --launch-type FARGATE \
  --count 1 \
  --query 'tasks[0].taskArn' --output text)
TASK_ID="${TASK_ARN##*/}"
echo "    task ${TASK_ID} is RUNNING"

# NOTE: do not read the port from `describe-tasks` on this build — its
# networkBindings echo the containerPort back as the hostPort (reports 8080 when
# the real binding is ${HOST_PORT}). `docker port` tells the truth.
#
# Beware `[ -n "$x" ] && y=...` here: when the test is false the whole line
# returns non-zero, and under `set -e` the script exits SILENTLY. Use a real if.
CONTAINER="floci-ecs-${TASK_ID}-app"
ACTUAL=$(docker port "$CONTAINER" "${CONTAINER_PORT}/tcp" 2>/dev/null | head -1 | sed 's/.*://' || true)
if [ -n "$ACTUAL" ]; then
  HOST_PORT="$ACTUAL"
else
  echo "Task ${TASK_ID} is running, but container ${CONTAINER} publishes no host" >&2
  echo "port for ${CONTAINER_PORT}/tcp. Usually something else already holds ${HOST_PORT}." >&2
  echo "  check:  docker ps --filter name=floci-ecs- ; lsof -nP -iTCP:${HOST_PORT} -sTCP:LISTEN" >&2
  echo "  retry:  ORDER_API_PORT=9090 ./03-real-infra/setup.sh" >&2
  exit 1
fi
echo "    backed by container ${CONTAINER}, published on host port ${HOST_PORT}"

echo "==> ECS: waiting for the app to answer"
BASE="http://localhost:${HOST_PORT}"
READY=""
for _ in $(seq 1 60); do
  if curl -sf -m 3 "${BASE}/q/health" >/dev/null 2>&1; then READY=1; break; fi
  sleep 1
done
if [ -z "$READY" ]; then
  echo "The task started but ${BASE}/q/health never answered. Inspect it with:" >&2
  echo "    docker logs ${CONTAINER}" >&2
  exit 1
fi
echo "    healthy at ${BASE}/q/health"

# ---------------------------------------------------------------------------
# 3. EKS: real Kubernetes via k3s.
# ---------------------------------------------------------------------------
echo "==> EKS: cluster (backed by k3s)"
if aws eks describe-cluster --name "$EKS_CLUSTER" >/dev/null 2>&1; then
  echo "    cluster exists"
else
  aws eks create-cluster \
    --name "$EKS_CLUSTER" \
    --role-arn "arn:aws:iam::${ACCOUNT}:role/eks" \
    --resources-vpc-config subnetIds=subnet-12345 >/dev/null
fi

# Bounded, so a cluster that failed to create reports an error instead of
# printing "still creating..." forever.
echo "==> EKS: waiting for ACTIVE (up to ${EKS_TIMEOUT_SECONDS}s)"
deadline=$((SECONDS + EKS_TIMEOUT_SECONDS))
until [ "$(aws eks describe-cluster --name "$EKS_CLUSTER" --query cluster.status --output text 2>/dev/null || true)" = "ACTIVE" ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "Cluster '${EKS_CLUSTER}' never reached ACTIVE. Inspect it with:" >&2
    echo "    aws eks describe-cluster --name ${EKS_CLUSTER}" >&2
    exit 1
  fi
  echo "    still creating..."
  sleep 5
done

echo "==> EKS: wiring kubectl"
aws eks update-kubeconfig --name "$EKS_CLUSTER" >/dev/null

# k3s keeps its state in a named Docker volume (floci-eks-<cluster>) that OUTLIVES
# the container. Remove the container without the volume — which is what a normal
# teardown does — and the next `create-cluster` starts a container with a new ID,
# which k3s takes as a new node name. It then restores the old state, and you end
# up with TWO nodes: the new Ready one, and a stale NotReady one whose pods hang
# in Terminating forever and wedge `kubectl rollout status`.
#
# Reap those stale nodes so the rollout below can actually finish.
#
# Match on identity, NOT on NotReady: a node that has only just registered is
# NotReady for its first few seconds too, and deleting the live node out from
# under the Deployment would be a much worse bug than the one we're fixing. The
# live node's name is the k3s container's hostname (its container ID).
LIVE_NODE=$(docker inspect --format '{{.Config.Hostname}}' "floci-eks-${EKS_CLUSTER}" 2>/dev/null || true)
for node in $(kubectl get nodes --no-headers 2>/dev/null | awk '{print $1}'); do
  [ "$node" = "$LIVE_NODE" ] && continue
  echo "    removing stale node ${node} (left behind by a previous cluster)"
  kubectl delete node "$node" --timeout=30s >/dev/null 2>&1 || true
  # Its pods can never terminate gracefully — the kubelet backing them is gone.
  kubectl get pods --all-namespaces --field-selector "spec.nodeName=${node}" \
    -o custom-columns=NS:.metadata.namespace,N:.metadata.name --no-headers 2>/dev/null |
    while read -r ns name; do
      kubectl delete pod "$name" -n "$ns" --force --grace-period=0 >/dev/null 2>&1 || true
    done
done

# The node registers a moment before it is schedulable. Without this, the rollout
# below can sit waiting on a node that isn't ready to take pods yet.
if [ -n "$LIVE_NODE" ]; then
  kubectl wait --for=condition=Ready "node/${LIVE_NODE}" --timeout=120s >/dev/null 2>&1 || true
fi

kubectl get nodes

# ---------------------------------------------------------------------------
# 4. Deploy the SAME image to Kubernetes. One image, two compute shapes.
# ---------------------------------------------------------------------------
K3S_CONTAINER="floci-eks-${EKS_CLUSTER}"

# k3s has its own containerd — it cannot see images in the host's Docker daemon,
# and there's no registry to pull from. Ship the image over directly.
echo "==> EKS: importing ${IMAGE} into the cluster's containerd"
docker save "$IMAGE" | docker exec -i "$K3S_CONTAINER" ctr -n k8s.io images import - >/dev/null 2>&1 || {
  echo "Could not import ${IMAGE} into ${K3S_CONTAINER}." >&2
  exit 1
}
echo "    imported"

# A pod can't resolve host.docker.internal the way an ECS task can, so it reaches
# the Floci edge through the Docker bridge gateway instead. Discover it rather
# than hardcoding 172.17.0.1, which isn't guaranteed.
GATEWAY=$(docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
GATEWAY="${GATEWAY:-172.17.0.1}"
POD_ENDPOINT="${K8S_FLOCI_ENDPOINT:-http://${GATEWAY}:4566}"
echo "==> EKS: deploying order-api (pods will reach Floci at ${POD_ENDPOINT})"

# Was it already deployed? Decides whether we need to force new pods below.
EXISTED=""
kubectl get deployment order-api >/dev/null 2>&1 && EXISTED=1

# The manifest ships with the usual gateway (172.17.0.1) hardcoded, so that a
# plain `kubectl apply -f k8s/order-api.yaml` works on its own — the README walks
# people through exactly that. Here we swap in the gateway we actually discovered,
# for the rare host where it differs. Same file, no placeholder to trip over.
MANIFEST=$(mktemp)
trap 'rm -f "$MANIFEST"' EXIT
sed "s|http://172.17.0.1:4566|${POD_ENDPOINT}|" "$here/k8s/order-api.yaml" > "$MANIFEST"
kubectl apply -f "$MANIFEST" >/dev/null

# `apply` is a no-op when the manifest hasn't changed, so on a re-run with a
# freshly rebuilt image the old pods would keep serving stale code. Force new
# ones. Only on a re-run, though: restarting a Deployment that is still doing its
# first rollout kills the pods mid-start and leaves an ugly Errored pod behind.
if [ -n "$EXISTED" ]; then
  kubectl rollout restart deployment/order-api >/dev/null
fi

if ! kubectl rollout status deployment/order-api --timeout=120s; then
  echo "The Deployment never became ready. Inspect it with:" >&2
  echo "    kubectl get pods && kubectl logs deployment/order-api" >&2
  exit 1
fi

# A rolling restart leaves the previous ReplicaSet's terminating pod showing as
# `Error` for a few seconds before Kubernetes garbage-collects it. Harmless, but
# it puts a red line on the projector right at the punchline. Reap it first.
kubectl delete pod -l app=order-api --field-selector=status.phase=Failed \
  --ignore-not-found >/dev/null 2>&1 || true

kubectl get pods -l app=order-api

cat <<EOF

==> Done. The same image is now serving from BOTH compute shapes.

    ECS — a real container, published straight to a host port:
      open     ${BASE}/
      orders   curl ${BASE}/orders
      health   curl ${BASE}/q/health
      proof    docker ps | grep floci-ecs

    EKS — the same image, two pods, on real Kubernetes:
      nodes    kubectl get nodes
      pods     kubectl get pods -l app=order-api
      logs     kubectl logs -l app=order-api --tail=5
      reach it kubectl port-forward svc/order-api 8082:8080
               curl http://localhost:8082/orders

    Both read the same DynamoDB table. Place another order with the Module 1 CLI
    and both will serve it:
      java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
EOF

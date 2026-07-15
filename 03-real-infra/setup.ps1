#Requires -Version 5.1
# Catch-up for the finale (Windows): the Quarkus order-api running as a real ECS
# container, plus a real Kubernetes cluster (EKS, backed by k3s).
#
# Idempotent: safe to re-run. Assumes `floci start` is up and the Floci env is
# set in this session (run `. .\00-setup\floci-env.ps1` first).
#
# The API serves the orders Module 1 produced, so this script bootstraps Module 1
# state if it is missing. Fall behind anywhere and this one script catches you up.
#
# Resource note: ECS and EKS together are fine on most laptops; on 8 GB machines
# run them one at a time (comment out the EKS section).

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

$ACCOUNT = "000000000000"
$REGION = if ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { "us-east-1" }

# --- ECS ---
$ECS_CLUSTER = "workshop"
$FAMILY = "order-api"
$IMAGE = "order-api:1.0"
$CONTAINER_PORT = 8080
# 8080 is a popular port (floci-ui, anyone's dev server), so publish on 8081.
# Override if that one is taken too:  $env:ORDER_API_PORT=9090; .\03-real-infra\setup.ps1
$HOST_PORT = if ($env:ORDER_API_PORT) { $env:ORDER_API_PORT } else { "8081" }

# The endpoint the TASK CONTAINER uses to call back into the Floci edge on the
# host. Floci 1.5.31 does not inject AWS_* into ECS task containers (Lambda gets
# it, ECS does not), so we pass it explicitly in the task definition.
# Docker Desktop on Windows resolves host.docker.internal natively.
$TASK_ENDPOINT = if ($env:ORDERS_API_ENDPOINT) { $env:ORDERS_API_ENDPOINT } else { "http://host.docker.internal:4566" }

# --- EKS ---
$EKS_CLUSTER = "demo"
$EKS_TIMEOUT_SECONDS = 300

aws sts get-caller-identity *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Cannot reach an AWS endpoint. Is Floci running, and did you run:"
    Write-Host '    floci start; . .\00-setup\floci-env.ps1'
    exit 1
}

# -----------------------------------------------------------------------------
# 0. Module 1 state. The API has nothing to serve without it.
# -----------------------------------------------------------------------------
Write-Host "==> Module 1 pipeline (the data the API serves)"
aws dynamodb describe-table --table-name orders *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    orders table exists"
} else {
    Write-Host "    orders table missing, running 01-events-core\setup.ps1"
    & (Join-Path $root "01-events-core\setup.ps1") | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# An empty table makes for a dull demo. Seed one order through the real Module 1
# pipeline (SQS -> Lambda -> DynamoDB) rather than writing to DynamoDB directly,
# so what the API serves genuinely came out the far end of the pipeline.
$COUNT = aws dynamodb scan --table-name orders --query Count --output text 2>$null
if ($LASTEXITCODE -ne 0) { $COUNT = "0" }
if ($COUNT -eq "0") {
    Write-Host "    table is empty, sending a sample order through SQS -> Lambda"
    $QUEUE_URL = aws sqs get-queue-url --queue-name order-events --query QueueUrl --output text
    aws sqs send-message `
        --queue-url $QUEUE_URL `
        --message-body "file://$root\01-events-core\events\sample-order.json" | Out-Null

    foreach ($i in 1..30) {
        $COUNT = aws dynamodb scan --table-name orders --query Count --output text 2>$null
        if ($LASTEXITCODE -ne 0) { $COUNT = "0" }
        if ($COUNT -ne "0") { break }
        Start-Sleep -Seconds 2
    }
    if ($COUNT -eq "0") {
        Write-Host "    the Lambda has not written the order yet; the API will start empty."
        Write-Host "    Check it with:  docker ps | Select-String lambda"
    }
}
Write-Host "    $COUNT order(s) in DynamoDB"

# Anyone who fell behind and ran only THIS script has no order-cli jar, and the
# closing message below tells them to run it. Build it if it's missing.
$CLI_JAR = Join-Path $root "01-events-core\order-cli\target\quarkus-app\quarkus-run.jar"
if (-not (Test-Path $CLI_JAR)) {
    Write-Host "    building the Module 1 CLI (you'll want it at the end of this module)"
    Push-Location (Join-Path $root "01-events-core\order-cli")
    mvn -q package
    $ok = $LASTEXITCODE
    Pop-Location
    if ($ok -ne 0) { exit 1 }
}

# -----------------------------------------------------------------------------
# 1. Build the app and bake it into a local image.
# -----------------------------------------------------------------------------
# No ECR, no docker push, no registry login. Floci's ECS resolves the image from
# the local Docker daemon and only pulls when it is absent, so a plain local tag
# is all a task definition needs.
Write-Host "==> Building order-api (Quarkus)"
Push-Location (Join-Path $here "order-api")
mvn -q package
$ok = $LASTEXITCODE
Pop-Location
if ($ok -ne 0) { exit 1 }

Write-Host "==> Building the container image $IMAGE"
docker build -q -t $IMAGE (Join-Path $here "order-api") | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "    built $IMAGE"

# -----------------------------------------------------------------------------
# 2. ECS: cluster, task definition, task.
# -----------------------------------------------------------------------------
Write-Host "==> ECS: cluster"
$STATUS = aws ecs describe-clusters --clusters $ECS_CLUSTER `
    --query 'clusters[0].status' --output text 2>$null
if ($LASTEXITCODE -ne 0) { $STATUS = "None" }
if ($STATUS -eq "ACTIVE") {
    Write-Host "    cluster $ECS_CLUSTER exists"
} else {
    aws ecs create-cluster --cluster-name $ECS_CLUSTER | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Write-Host "    created cluster $ECS_CLUSTER"
}

# Two load-bearing choices here, both easy to get wrong:
#
#   network-mode bridge  — awsvpc DISCARDS the literal hostPort and hands you a
#                          random one instead, so the URL we print below would be
#                          wrong. Do not switch this to awsvpc.
#   an explicit hostPort — a hostPort of 0 (or absent) also means a random port.
#
# For the same reason we do NOT pass --requires-compatibilities FARGATE: it
# forces awsvpc. (--launch-type FARGATE on run-task is fine and does not.)
#
# The JSON goes through a temp file: quoting a JSON literal on a PowerShell
# command line mangles it long before the AWS CLI sees it.
Write-Host "==> ECS: task definition"
$containerDefs = @"
[{
  "name": "app",
  "image": "$IMAGE",
  "essential": true,
  "memory": 1024,
  "portMappings": [{"containerPort": $CONTAINER_PORT, "hostPort": $HOST_PORT, "protocol": "tcp"}],
  "environment": [
    {"name": "AWS_ENDPOINT_URL",      "value": "$TASK_ENDPOINT"},
    {"name": "AWS_REGION",            "value": "$REGION"},
    {"name": "AWS_ACCESS_KEY_ID",     "value": "test"},
    {"name": "AWS_SECRET_ACCESS_KEY", "value": "test"},
    {"name": "ORDERS_TABLE",          "value": "orders"}
  ]
}]
"@
$taskdefFile = Join-Path $env:TEMP "order-api-taskdef.json"
Set-Content -Path $taskdefFile -Value $containerDefs -Encoding ascii

$REVISION = aws ecs register-task-definition `
    --family $FAMILY `
    --network-mode bridge `
    --container-definitions "file://$taskdefFile" `
    --query 'taskDefinition.revision' --output text
if ($LASTEXITCODE -ne 0) { exit 1 }
Remove-Item $taskdefFile -ErrorAction SilentlyContinue
Write-Host "    registered ${FAMILY}:${REVISION}"

# run-task always launches a NEW task, so re-running this unguarded would pile up
# containers fighting over the host port. Stop what is running first; that also
# guarantees the task picks up the image we just rebuilt instead of leaving a
# stale one serving.
Write-Host "==> ECS: stopping any previous order-api task"
$RUNNING = aws ecs list-tasks --cluster $ECS_CLUSTER --desired-status RUNNING `
    --query 'taskArns' --output text 2>$null
if ($LASTEXITCODE -eq 0 -and $RUNNING -and $RUNNING -ne "None") {
    foreach ($arn in ($RUNNING -split '\s+')) {
        if (-not $arn) { continue }
        aws ecs stop-task --cluster $ECS_CLUSTER --task $arn *> $null
        Write-Host "    stopped $($arn.Split('/')[-1])"
    }
}

# Give Docker a moment to actually release the host port.
foreach ($i in 1..15) {
    $stillUp = docker ps --filter "name=floci-ecs-" --format '{{.Names}}' 2>$null
    if (-not $stillUp) { break }
    Start-Sleep -Seconds 1
}

# Floci's default storage is in-memory, so restarting it makes Floci FORGET its
# tasks — while the task containers keep running, and keep holding the host
# port. `stop-task` above can't help: there is no task to stop any more. The new
# container then fails to bind the port and the whole module dies in a confusing
# way. Reap the orphans directly.
$ORPHANS = docker ps --filter "name=floci-ecs-" --format '{{.Names}}' 2>$null
foreach ($c in $ORPHANS) {
    if (-not $c) { continue }
    Write-Host "    removing orphaned container $c (Floci restarted and lost track of it)"
    docker rm -f $c *> $null
}

Write-Host "==> ECS: running the task"
$TASK_ARN = aws ecs run-task `
    --cluster $ECS_CLUSTER `
    --task-definition "${FAMILY}:${REVISION}" `
    --launch-type FARGATE `
    --count 1 `
    --query 'tasks[0].taskArn' --output text
if ($LASTEXITCODE -ne 0) { exit 1 }
$TASK_ID = $TASK_ARN.Split('/')[-1]
Write-Host "    task $TASK_ID is RUNNING"

# NOTE: do not read the port from `describe-tasks` on this build — its
# networkBindings echo the containerPort back as the hostPort (reports 8080 when
# the real binding is $HOST_PORT). `docker port` tells the truth.
$CONTAINER = "floci-ecs-$TASK_ID-app"
$portLine = docker port $CONTAINER "$CONTAINER_PORT/tcp" 2>$null | Select-Object -First 1
$ACTUAL = if ($portLine) { ($portLine -split ':')[-1].Trim() } else { "" }
if ($ACTUAL) {
    $HOST_PORT = $ACTUAL
} else {
    Write-Host "Task $TASK_ID is running, but container $CONTAINER publishes no host"
    Write-Host "port for $CONTAINER_PORT/tcp. Usually something else already holds $HOST_PORT."
    Write-Host "  check:  docker ps --filter name=floci-ecs- ; netstat -ano | Select-String ':$HOST_PORT'"
    Write-Host "  retry:  `$env:ORDER_API_PORT=9090; .\03-real-infra\setup.ps1"
    exit 1
}
Write-Host "    backed by container $CONTAINER, published on host port $HOST_PORT"

Write-Host "==> ECS: waiting for the app to answer"
$BASE = "http://localhost:$HOST_PORT"
$READY = $false
foreach ($i in 1..60) {
    try {
        Invoke-WebRequest -Uri "$BASE/q/health" -UseBasicParsing -TimeoutSec 3 | Out-Null
        $READY = $true
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}
if (-not $READY) {
    Write-Host "The task started but $BASE/q/health never answered. Inspect it with:"
    Write-Host "    docker logs $CONTAINER"
    exit 1
}
Write-Host "    healthy at $BASE/q/health"

# -----------------------------------------------------------------------------
# 3. EKS: real Kubernetes via k3s.
# -----------------------------------------------------------------------------
Write-Host "==> EKS: cluster (backed by k3s)"
aws eks describe-cluster --name $EKS_CLUSTER *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "    cluster exists"
} else {
    aws eks create-cluster `
        --name $EKS_CLUSTER `
        --role-arn "arn:aws:iam::${ACCOUNT}:role/eks" `
        --resources-vpc-config subnetIds=subnet-12345 | Out-Null
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# Bounded, so a cluster that failed to create reports an error instead of
# printing "still creating..." forever.
Write-Host "==> EKS: waiting for ACTIVE (up to ${EKS_TIMEOUT_SECONDS}s)"
$deadline = (Get-Date).AddSeconds($EKS_TIMEOUT_SECONDS)
while ($true) {
    $status = aws eks describe-cluster --name $EKS_CLUSTER --query cluster.status --output text 2>$null
    if ($status -eq "ACTIVE") { break }
    if ((Get-Date) -ge $deadline) {
        Write-Host "Cluster '$EKS_CLUSTER' never reached ACTIVE. Inspect it with:"
        Write-Host "    aws eks describe-cluster --name $EKS_CLUSTER"
        exit 1
    }
    Write-Host "    still creating..."
    Start-Sleep -Seconds 5
}

Write-Host "==> EKS: wiring kubectl"
aws eks update-kubeconfig --name $EKS_CLUSTER | Out-Null

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
$LIVE_NODE = docker inspect --format '{{.Config.Hostname}}' "floci-eks-$EKS_CLUSTER" 2>$null
$nodes = kubectl get nodes --no-headers 2>$null | ForEach-Object { ($_ -split '\s+')[0] }
foreach ($node in $nodes) {
    if (-not $node -or $node -eq $LIVE_NODE) { continue }
    Write-Host "    removing stale node $node (left behind by a previous cluster)"
    kubectl delete node $node --timeout=30s *> $null
    # Its pods can never terminate gracefully — the kubelet backing them is gone.
    kubectl get pods --all-namespaces --field-selector "spec.nodeName=$node" `
        -o custom-columns=NS:.metadata.namespace,N:.metadata.name --no-headers 2>$null |
        ForEach-Object {
            $parts = $_ -split '\s+'
            if ($parts.Count -ge 2) {
                kubectl delete pod $parts[1] -n $parts[0] --force --grace-period=0 *> $null
            }
        }
}

# The node registers a moment before it is schedulable. Without this, the rollout
# below can sit waiting on a node that isn't ready to take pods yet.
if ($LIVE_NODE) {
    kubectl wait --for=condition=Ready "node/$LIVE_NODE" --timeout=120s *> $null
}

kubectl get nodes

# -----------------------------------------------------------------------------
# 4. Deploy the SAME image to Kubernetes. One image, two compute shapes.
# -----------------------------------------------------------------------------
$K3S_CONTAINER = "floci-eks-$EKS_CLUSTER"

# k3s has its own containerd — it cannot see images in the host's Docker daemon,
# and there's no registry to pull from. Ship the image over directly.
#
# NOT `docker save | docker exec -i` here: piping binary data through PowerShell
# re-encodes it as text and corrupts the tar. Save to a file and `docker cp` it.
Write-Host "==> EKS: importing $IMAGE into the cluster's containerd"
$tarFile = Join-Path $env:TEMP "order-api-image.tar"
docker save $IMAGE -o $tarFile
if ($LASTEXITCODE -ne 0) { exit 1 }
docker cp $tarFile "${K3S_CONTAINER}:/tmp/order-api-image.tar"
if ($LASTEXITCODE -ne 0) {
    Remove-Item $tarFile -ErrorAction SilentlyContinue
    Write-Host "Could not copy $IMAGE into $K3S_CONTAINER."
    exit 1
}
docker exec $K3S_CONTAINER ctr -n k8s.io images import /tmp/order-api-image.tar *> $null
$ok = $LASTEXITCODE
docker exec $K3S_CONTAINER rm -f /tmp/order-api-image.tar *> $null
Remove-Item $tarFile -ErrorAction SilentlyContinue
if ($ok -ne 0) {
    Write-Host "Could not import $IMAGE into $K3S_CONTAINER."
    exit 1
}
Write-Host "    imported"

# A pod can't resolve host.docker.internal the way an ECS task can, so it reaches
# the Floci edge through the Docker bridge gateway instead. Discover it rather
# than hardcoding 172.17.0.1, which isn't guaranteed.
$GATEWAY = docker network inspect bridge --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>$null
if (-not $GATEWAY) { $GATEWAY = "172.17.0.1" }
$POD_ENDPOINT = if ($env:K8S_FLOCI_ENDPOINT) { $env:K8S_FLOCI_ENDPOINT } else { "http://${GATEWAY}:4566" }
Write-Host "==> EKS: deploying order-api (pods will reach Floci at $POD_ENDPOINT)"

# Was it already deployed? Decides whether we need to force new pods below.
kubectl get deployment order-api *> $null
$EXISTED = ($LASTEXITCODE -eq 0)

# The manifest ships with the usual gateway (172.17.0.1) hardcoded, so that a
# plain `kubectl apply -f k8s/order-api.yaml` works on its own — the README walks
# people through exactly that. Here we swap in the gateway we actually discovered,
# for the rare host where it differs. Same file, no placeholder to trip over.
$MANIFEST = Join-Path $env:TEMP "order-api-manifest.yaml"
(Get-Content (Join-Path $here "k8s\order-api.yaml") -Raw).Replace("http://172.17.0.1:4566", $POD_ENDPOINT) |
    Set-Content -Path $MANIFEST -Encoding ascii
kubectl apply -f $MANIFEST | Out-Null
$ok = $LASTEXITCODE
Remove-Item $MANIFEST -ErrorAction SilentlyContinue
if ($ok -ne 0) { exit 1 }

# `apply` is a no-op when the manifest hasn't changed, so on a re-run with a
# freshly rebuilt image the old pods would keep serving stale code. Force new
# ones. Only on a re-run, though: restarting a Deployment that is still doing its
# first rollout kills the pods mid-start and leaves an ugly Errored pod behind.
if ($EXISTED) {
    kubectl rollout restart deployment/order-api | Out-Null
}

kubectl rollout status deployment/order-api --timeout=120s
if ($LASTEXITCODE -ne 0) {
    Write-Host "The Deployment never became ready. Inspect it with:"
    Write-Host "    kubectl get pods; kubectl logs deployment/order-api"
    exit 1
}

# A rolling restart leaves the previous ReplicaSet's terminating pod showing as
# `Error` for a few seconds before Kubernetes garbage-collects it. Harmless, but
# it puts a red line on the projector right at the punchline. Reap it first.
kubectl delete pod -l app=order-api --field-selector=status.phase=Failed `
    --ignore-not-found *> $null

kubectl get pods -l app=order-api

Write-Host @"

==> Done. The same image is now serving from BOTH compute shapes.

    ECS — a real container, published straight to a host port:
      open     $BASE/
      orders   curl.exe $BASE/orders
      health   curl.exe $BASE/q/health
      proof    docker ps | Select-String floci-ecs

    EKS — the same image, two pods, on real Kubernetes:
      nodes    kubectl get nodes
      pods     kubectl get pods -l app=order-api
      logs     kubectl logs -l app=order-api --tail=5
      reach it kubectl port-forward svc/order-api 8082:8080
               curl.exe http://localhost:8082/orders

    Both read the same DynamoDB table. Place another order with the Module 1 CLI
    and both will serve it:
      java -jar 01-events-core\order-cli\target\quarkus-app\quarkus-run.jar place --customer "Grace Hopper"
"@

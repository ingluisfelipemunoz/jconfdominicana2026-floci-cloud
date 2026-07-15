# Module 3. Real infra finale: ECS and EKS

**55 minutes.** The headline, and the moment the whole workshop closes on itself.

You'll take a **second Quarkus app** — a web API — and deploy it **twice from one
image**: once as a real **ECS** container, and once as a Deployment on a real
**Kubernetes** cluster (EKS, backed by k3s). Both serve the very orders your
Module 1 CLI placed and your Lambda processed. At the same time.

One image, two compute shapes, five AWS services, no cloud account.

---

## Required tools

| Tool | Why |
|---|---|
| **Docker**, running | ECS runs a real container; EKS runs a real k3s cluster |
| **AWS CLI v2** | Creates the ECS cluster, task definition, and EKS cluster |
| **Java 21+ and Maven** | Builds the `order-api` app |
| **kubectl** | Deploys to and drives the Kubernetes cluster |

**Before you start**, in this terminal:

```bash
floci start              # if it isn't already up
eval "$(floci env)"      # every new terminal needs this
```

**State you need:** Module 1's pipeline. If it's missing, the setup script
recreates it for you — including building the Module 1 CLI — so you can jump
straight here.

**Resource note:** ECS and EKS together are fine on most laptops. On an 8 GB
machine, run them one at a time (comment out the EKS block in `setup.sh`).

---

## The fast path

```bash
./03-real-infra/setup.sh           # macOS / Linux
.\03-real-infra\setup.ps1          # Windows (PowerShell)
```

About 30 seconds from an empty cloud to both deployments live. It's idempotent —
re-run it any time. Then jump to [The finale](#the-finale) below.

The rest of this page walks through what it did, so you can do it by hand.

---

## Part 1: ECS

### 1. Build the app and bake an image

```bash
cd 03-real-infra/order-api && mvn -q package && cd -
docker build -t order-api:1.0 03-real-infra/order-api
```

**No ECR. No `docker push`. No registry login.** Floci's ECS resolves a task
definition's image from your local Docker daemon and only pulls when it's absent,
so a plain local tag is all you need.

### 2. Create a cluster

```bash
aws ecs create-cluster --cluster-name workshop
```

### 3. Register a task definition

```bash
aws ecs register-task-definition \
  --family order-api \
  --network-mode bridge \
  --container-definitions '[{
    "name": "app",
    "image": "order-api:1.0",
    "essential": true,
    "memory": 1024,
    "portMappings": [{"containerPort": 8080, "hostPort": 8081, "protocol": "tcp"}],
    "environment": [
      {"name": "AWS_ENDPOINT_URL", "value": "http://host.docker.internal:4566"}
    ]
  }]'
```

**Three choices here are load-bearing.** Get any of them wrong and the demo breaks
in a confusing way:

| Choice | Why it matters |
|---|---|
| `--network-mode bridge` | `awsvpc` **silently discards your `hostPort`** and gives you a random one. Your URL would be wrong. |
| An explicit `hostPort` | `0`, or omitting it, also means a random port. |
| **No** `--requires-compatibilities FARGATE` | It forces `awsvpc`. (`--launch-type FARGATE` on `run-task` is fine and does not.) |
| `"memory": 1024` | A hard Docker memory limit. `512` will OOM-kill a JVM app. |

### 4. Run it

```bash
aws ecs run-task --cluster workshop --task-definition order-api \
  --launch-type FARGATE --count 1
```

This returns once the task is `RUNNING` — the container is already up.

### 5. Use it

```bash
curl http://localhost:8081/q/health     # {"status":"UP"}
curl http://localhost:8081/orders       # the orders your CLI placed
open  http://localhost:8081/            # or just open it in a browser

docker ps | grep floci-ecs              # the real container behind it
```

---

## Part 2: EKS — a real Kubernetes cluster

### 6. Create the cluster

```bash
aws eks create-cluster --name demo \
  --role-arn arn:aws:iam::000000000000:role/eks \
  --resources-vpc-config subnetIds=subnet-12345

aws eks describe-cluster --name demo --query cluster.status   # poll until ACTIVE
```

Reaches `ACTIVE` in 10–15 seconds.

### 7. Point kubectl at it

```bash
aws eks update-kubeconfig --name demo
kubectl get nodes
```

```
NAME           STATUS   ROLES           AGE   VERSION
0f650532d2a9   Ready    control-plane   5s    v1.34.1+k3s1
```

That's a real Kubernetes API server and a real `kubectl`. **Don't stop here —
deploy to it.**

### 8. Hand the image to the cluster

```bash
docker save order-api:1.0 | docker exec -i floci-eks-demo ctr -n k8s.io images import -
```

k3s runs **its own containerd**. It cannot see your Docker daemon's images, and
there's no registry to pull from — so you ship the image over directly.

### 9. Deploy

```bash
kubectl apply -f 03-real-infra/k8s/order-api.yaml
kubectl rollout status deployment/order-api
kubectl get pods -l app=order-api
```

```
NAME                         READY   STATUS    RESTARTS   AGE
order-api-5bcc7c557b-d8sql   1/1     Running   0          5s
order-api-5bcc7c557b-k7kx9   1/1     Running   0          5s
```

### 10. Reach it

```bash
kubectl port-forward svc/order-api 8082:8080
curl http://localhost:8082/orders
```

Floci publishes only the k3s **API server**, not arbitrary node ports, so
`port-forward` is how you get in. (A NodePort won't reach your host.)

---

## The finale

Both deployments are live. Place one more order and watch **both** serve it:

```bash
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar \
  place --customer "Katherine Johnson"

curl http://localhost:8081/orders    # the ECS container
curl http://localhost:8082/orders    # the Kubernetes pods
```

```
  ECS container   (localhost:8081):  Katherine Johnson, Ada Lovelace
  Kubernetes pods (localhost:8082):  Katherine Johnson, Ada Lovelace
```

A CLI you built → S3 and SQS → a real Lambda container → DynamoDB → an API you
built, running on both a real ECS container and a real Kubernetes cluster. On a
laptop. With no cloud account.

---

## The endpoint duality (read this — it explains most failures)

Your app is a stock AWS SDK app. It finds Floci through `AWS_ENDPOINT_URL`. But
**where Floci lives depends on where you're standing**, and this module has three
different vantage points:

| You are... | Floci is at... |
|---|---|
| On the host (running the jar, or the CLI) | `localhost:4566` — set for you by `eval "$(floci env)"` |
| **Inside an ECS container** Floci spawned | `host.docker.internal:4566` — the *host*, not your own localhost |
| **Inside a Kubernetes pod** | `172.17.0.1:4566` — the Docker bridge gateway. A pod cannot resolve `host.docker.internal` |

That's why the ECS task definition and the k8s manifest each set
`AWS_ENDPOINT_URL` explicitly. Floci injects it automatically for **Lambda**
containers, but (as of server 1.5.31) **not** for ECS tasks or pods.

Get this wrong and you see a very specific, very confusing symptom: **`/q/health`
passes while `/orders` hangs forever** — because the app is healthy, it's just
patiently trying to reach a Floci that isn't at the address it was given.

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `port is already allocated` on 8081 | Something else owns 8081 (often `floci-ui`, which defaults to 8080) | `ORDER_API_PORT=9090 ./03-real-infra/setup.sh` |
| You restarted Floci, and now the module fails | Floci's storage is in-memory, so a restart makes it **forget its ECS tasks — while the containers keep running and keep holding port 8081** | Just re-run `./03-real-infra/setup.sh`. It reaps orphaned `floci-ecs-*` containers automatically |
| **`/q/health` is fine but `/orders` hangs** | The container/pod can't reach the Floci edge. See the duality table above | ECS: `ORDERS_API_ENDPOINT=http://172.17.0.1:4566 ./03-real-infra/setup.sh`. Pods: `K8S_FLOCI_ENDPOINT=http://<gw>:4566 ...` |
| The URL works but on a port you didn't ask for | You used `awsvpc`, or omitted `hostPort` | Use `--network-mode bridge` **and** an explicit `hostPort` |
| `aws ecs describe-tasks` shows the wrong port | **Known Floci bug (1.5.31):** `networkBindings` echo the *container* port as the `hostPort` | Trust `docker port` / `docker ps`, not `describe-tasks` |
| Task starts, then dies immediately | `memory` too low — the JVM gets OOM-killed | Use `1024`, not `512` |
| Pods stuck in `ErrImagePull` | The image isn't in k3s's containerd, or `imagePullPolicy: Never` is missing | Re-run the setup script — it does the `ctr images import` |
| `kubectl` can't reach the cluster | The cluster isn't `ACTIVE` yet | Poll `aws eks describe-cluster --name demo --query cluster.status` first |
| A pod shows `Error` right after a re-run | A previous ReplicaSet's pod terminating. Kubernetes reaps it in a few seconds | Cosmetic. Ignore it, or `kubectl get pods` again |
| `delete-cluster` fails | ECS refuses while tasks are running | Stop the tasks first |
| Everything is slow / Docker is thrashing | ECS + EKS + Lambda on an 8 GB laptop | Run ECS and EKS one at a time |

**On Linux:** `host.docker.internal` may not resolve inside containers. Both
escape hatches above (`ORDERS_API_ENDPOINT`, `K8S_FLOCI_ENDPOINT`) exist for this.
A default-DROP `ufw` policy will also block the container → host callback entirely;
`sudo ufw allow in on docker0` fixes it.

---

## Cleaning up

This module leaves the heaviest footprint: an ECS task container, a k3s cluster,
a Docker volume holding the cluster's state, and the `order-api:1.0` image.

```bash
./00-setup/teardown.sh
```

If you'd rather do it by hand, don't forget the **volume** — it's the step people
miss, and leaving it behind makes the *next* EKS cluster come up with a stale
second node whose pods hang in `Terminating` forever:

```bash
kubectl delete -f 03-real-infra/k8s/order-api.yaml
aws ecs delete-cluster --cluster workshop        # stop any tasks first
aws eks delete-cluster --name demo
docker volume rm floci-eks-demo                  # <- the one people forget
docker rmi order-api:1.0
```

---

## Files here

| Path | What it is |
|---|---|
| `order-api/` | The Quarkus REST API. Has its own [README](order-api/README.md) |
| `k8s/order-api.yaml` | The Kubernetes Deployment + Service |
| `setup.sh` / `setup.ps1` | Idempotent catch-up: does all ten steps above |

---

## Catch-up

```bash
./03-real-infra/setup.sh
```

Recreates Module 1's pipeline if it's missing, seeds an order, builds everything,
and deploys to both ECS and EKS.

---

**Next:** [Module 4 — migrate and multi-cloud](../04-migrate-multicloud/README.md)

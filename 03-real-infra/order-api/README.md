# order-api

A real Quarkus web API, built on the AWS SDK for Java v2, that serves the orders
the Module 1 pipeline produced.

One image, deployed twice: as a real **ECS** container, and as a two-replica
**Deployment on the EKS cluster**. Same `orders` DynamoDB table as Module 1, same
image, two different compute shapes.

| Route | What it does |
|---|---|
| `/` | A landing page, so hitting the base URL in a browser shows something |
| `/orders` | Every order in DynamoDB |
| `/orders/{orderId}` | One order |
| `/q/health` | Readiness (how the setup script knows the task is up) |

## Run it

The catch-up script does everything — builds the app and the image, deploys it to
ECS, creates the EKS cluster, and deploys the same image there too:

```bash
./03-real-infra/setup.sh

curl http://localhost:8081/orders             # from the ECS container

kubectl get pods -l app=order-api             # 2 pods on Kubernetes
kubectl port-forward svc/order-api 8082:8080
curl http://localhost:8082/orders             # the same orders, from Kubernetes
```

Then close the loop: place an order with the Module 1 CLI, and *both* serve it.

```bash
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
```

## How it gets onto ECS

```bash
mvn -q package
docker build -t order-api:1.0 .
```

There's **no ECR, no `docker push`, no registry login**. Floci's ECS resolves a
task definition's image from the local Docker daemon and only pulls when it's
absent, so a plain local tag like `order-api:1.0` is all you need.

Three things in the task definition are load-bearing (see `../setup.sh`):

- **`--network-mode bridge`.** `awsvpc` silently discards your literal `hostPort`
  and allocates a random one instead.
- **An explicit `hostPort`.** `0`, or omitting it, also means a random port.
- **No `--requires-compatibilities FARGATE`**, because it forces `awsvpc`.
  (`--launch-type FARGATE` on `run-task` is fine and does not.)

## How it gets onto Kubernetes

`../k8s/order-api.yaml` is a plain Deployment + Service. Two settings are specific
to a local cluster:

- **`imagePullPolicy: Never`.** The image is on your laptop, not in a registry.
  Without this, Kubernetes tries Docker Hub and you get `ErrImagePull`.
- **`AWS_ENDPOINT_URL` points at the Docker bridge gateway** (`172.17.0.1`), not
  `host.docker.internal` — a pod can't resolve that. `setup.sh` discovers the real
  gateway IP and substitutes it.

k3s runs its own containerd and cannot see the host Docker daemon's images, and
there's no registry in play, so the image is handed over directly:

```bash
docker save order-api:1.0 | docker exec -i floci-eks-demo ctr -n k8s.io images import -
```

Floci publishes only the k3s API server, not arbitrary node ports, so reach the
Service with `kubectl port-forward` rather than a NodePort.

## How it points at Floci

Nothing in the Java code is Floci-specific. `application.properties` configures a
stock DynamoDB client from stock AWS environment variables.

The one subtlety is the **endpoint duality**. On the host, `eval "$(floci env)"`
points `AWS_ENDPOINT_URL` at the Floci edge. But from inside a container that
*Floci itself spawned*, the edge is not on `localhost` — it's back on the host. So
the task definition passes `AWS_ENDPOINT_URL=http://host.docker.internal:4566`.

Floci injects that automatically for Lambda containers; as of server 1.5.31 it
does not for ECS tasks. Drop the env var and you get a confusing failure: `/q/health`
still passes while `/orders` hangs forever, because the SDK is patiently trying to
reach the container's own localhost.

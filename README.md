# Build a Whole Cloud Locally with Floci

Run, test, and ship a real cloud app on your laptop. No account required.

This is the attendee repo for the hands-on workshop. You'll build a real
**Quarkus** application that drives **S3**, **SQS**, and **DynamoDB**, with a
**Python Lambda** processing the events, all running locally on Floci. Then
you'll turn it into a fast, isolated integration test, and finish on real
infrastructure: a second Quarkus app deployed as a real **ECS** container serving
your orders back, and an **EKS** cluster you can point `kubectl` at.

> Facilitators: the full runbook lives in [`workshop.md`](workshop.md).
> The finished reference lives in [`SOLUTION.md`](SOLUTION.md).

---

## What you need

- **Docker** (Desktop or engine) running locally.
- **Java 21+** and **Maven** (for the two Quarkus apps and the Java test).
- **The AWS CLI** (v2). We use it with no real account.
- **`kubectl`** — you'll deploy to a real Kubernetes cluster in the finale.
- **[`act`](https://github.com/nektos/act)** (`brew install act`) for the capstone.
- ~8 GB free disk for the container images.

You do **not** need an AWS account, a credit card, or any cloud login.

---

## Before the workshop: run the preflight

Conference wifi cannot survive everyone pulling multi-gigabyte images at once.
**Please run this at home, on good wifi, before you arrive.**

```bash
# macOS / Linux
./00-setup/preflight.sh
```

```powershell
# Windows
.\00-setup\preflight.ps1
```

It checks your toolchain, installs the Floci CLI, pulls every image we need,
builds the two Quarkus apps so your Maven cache is warm, and runs a smoke test.
Expect it to take a while — that's the point, and it's why we do it at home.

If it doesn't pass, reply to the invite email and we'll help.

---

## Getting started (Module 0)

```bash
floci start
eval "$(floci env)"     # exports AWS_ENDPOINT_URL and dummy credentials
floci doctor            # verifies Docker, ports, and the socket

aws s3 mb s3://hello
aws dynamodb list-tables
```

Real AWS CLI output, zero account, in under a minute. That's the whole pitch.

---

## The app

The star of the workshop is `01-events-core/order-cli/`, a real Quarkus
command-line app built on the AWS SDK for Java v2:

```bash
# wire up the cloud resources + Lambda
./01-events-core/setup.sh

# build and run the app against Floci
cd 01-events-core/order-cli && mvn -q package
java -jar target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
java -jar target/quarkus-app/quarkus-run.jar get A-xxxxxxxx
```

`place` uploads the order to S3 and drops it on SQS. The Python Lambda in
`01-events-core/lambda/process-order/` picks it up off the queue and writes it to
DynamoDB. Then `get` reads it back. The whole loop runs on your laptop.

In Module 3 a second Quarkus app, `03-real-infra/order-api/`, serves those same
orders over HTTP — deployed **twice**, from one image, onto two different kinds of
compute:

```bash
./03-real-infra/setup.sh

# on ECS, as a real container
curl http://localhost:8081/orders

# and on real Kubernetes, as two pods on the EKS cluster
kubectl get nodes
kubectl get pods -l app=order-api
kubectl port-forward svc/order-api 8082:8080
curl http://localhost:8082/orders
```

Place another order with the CLI and both serve it. A CLI you built, a real Lambda
container, an ECS container, and a Kubernetes Deployment — all on your laptop, no
account.

---

## The arc

**Every module has its own README** with a step-by-step guide, the tools it needs,
and a table of common errors and their fixes. Start there.

**On Windows**, every script below has a PowerShell twin — swap `.sh` for `.ps1`
(and `eval "$(floci env)"` for `. .\00-setup\floci-env.ps1`).

| Module | You build | Catch-up |
|---|---|---|
| [0. Setup](00-setup/README.md) | A green environment and a fast win | (none) |
| [1. Event-driven core](01-events-core/README.md) | The Quarkus app feeds S3 and SQS, the Lambda writes DynamoDB | `./01-events-core/setup.sh` |
| [2. Make it CI-grade](02-testcontainers/README.md) | Isolated Testcontainers tests | `cd 02-testcontainers/java && mvn test` |
| [3. Real infra finale](03-real-infra/README.md) | One Quarkus API, deployed twice: a real ECS container, and a Deployment on a real Kubernetes cluster | `./03-real-infra/setup.sh` |
| [4. Migrate and multi-cloud](04-migrate-multicloud/README.md) | LocalStack swap, plus an Azure and GCP taste | `docker compose -f 04-migrate-multicloud/floci-after/compose.yaml up -d` |
| [5. Capstone](05-act-demo/README.md) | A GitHub Actions workflow run locally with `act`, against Floci | `./05-act-demo/run.sh` |

### Testing in your language

Module 2's suite is Java, so there's one thing to run in the room. But the
Testcontainers module isn't Java-only — it exists for five languages, and they
all expose the same shape (`getEndpoint()`, `getRegion()`, `getAccessKey()`,
`getSecretKey()`), so the test you write today ports directly:

| Language | Package |
|---|---|
| Java | `io.floci:testcontainers-floci` |
| Python | `testcontainers-floci` (PyPI) |
| Node.js | `@floci/testcontainers` (npm) |
| Go | `testcontainers-floci-go` |
| .NET | `testcontainers-floci` |

### The whole workshop, in order

Every step, start to finish. Each module's README explains what these do and how
to fix them when they don't.

```bash
# ---- Before the day (at home, on good wifi) ----
./00-setup/preflight.sh

# ---- Module 0: setup ----
floci start
eval "$(floci env)"                     # needed in EVERY new terminal
floci doctor
aws s3 mb s3://hello && aws dynamodb list-tables

# ---- Module 1: the event-driven core ----
./01-events-core/setup.sh
cd 01-events-core/order-cli && mvn -q package && cd -
JAR=01-events-core/order-cli/target/quarkus-app/quarkus-run.jar
java -jar $JAR place --customer "Grace Hopper"
aws s3 ls s3://orders/
docker ps | grep lambda                 # a real Lambda runtime container
java -jar $JAR get A-xxxxxxxx           # ~1-2s after place; retry if "not found yet"

# ---- Module 2: make it CI-grade ----
cd 02-testcontainers/java && mvn test && cd -

# ---- Module 3: real infra (ECS + EKS) ----
./03-real-infra/setup.sh
curl http://localhost:8081/orders                  # the ECS container
kubectl get nodes && kubectl get pods -l app=order-api
kubectl port-forward svc/order-api 8082:8080 &     # the Kubernetes pods
curl http://localhost:8082/orders
java -jar $JAR place --customer "Katherine Johnson" # both now serve it

# ---- Module 4: migrate + multi-cloud ----
# NOTE: needs port 4566, so Floci must stop. That WIPES Modules 0-3 state
# (storage is in-memory). Finish Module 3 first.
floci stop
docker compose -f 04-migrate-multicloud/floci-after/compose.yaml up -d
sleep 10
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
aws s3 ls | grep migrated-bucket        # the unchanged LocalStack init script ran
docker compose -f 04-migrate-multicloud/floci-after/compose.yaml down -v

# ---- Module 5: the capstone ----
./05-act-demo/run.sh                    # Floci must be stopped; the workflow brings its own

# ---- Want Modules 0-3 back? ----
floci start && eval "$(floci env)"
./03-real-infra/setup.sh                # rebuilds the whole pipeline, under a minute

# ---- When you're done: give your laptop back ----
./00-setup/teardown.sh                  # containers, volumes, kubeconfig contexts
./00-setup/teardown.sh --images         # ...plus the ~8 GB of images
```

### Fell behind?

Each module has an idempotent catch-up script that recreates its state from
scratch. Run the one for the module you want to be at and rejoin:

```bash
./03-real-infra/setup.sh
```

| Module | Catch-up | State it gets you to |
|---|---|---|
| 1. Event-driven core | `./01-events-core/setup.sh` | Quarkus app + Lambda wired across S3, SQS, DynamoDB |
| 2. CI-grade tests | `cd 02-testcontainers/java && mvn test` | Integration test written and passing |
| 3. Real infra finale | `./03-real-infra/setup.sh` | order-api serving from both an ECS container and 2 pods on EKS |
| 4. Migrate + multi-cloud | see `04-migrate-multicloud/` | LocalStack swap plus Azure and GCP taste |
| 5. Capstone | `./05-act-demo/run.sh` | GitHub Actions workflow running locally against Floci |

---

## Repo layout

One directory per module:

One directory per module, each with its own `README.md` — steps, tools, and a
common-errors table.

```
floci-workshop/
  00-setup/                  README + preflight, teardown, image list, a compose file for CI
  01-events-core/            README
    order-cli/               the Quarkus S3/SQS/DynamoDB app (+ README)
    lambda/process-order/    the Python process-order Lambda
    events/                  a sample order document
    setup.sh                 idempotent catch-up
  02-testcontainers/         README
    java/                    the Testcontainers suite
  03-real-infra/             README
    order-api/               the Quarkus REST API, run on both ECS and EKS (+ README)
    k8s/order-api.yaml       the Kubernetes Deployment + Service
    setup.sh                 ECS + EKS catch-up
  04-migrate-multicloud/     README
    localstack-before/  floci-after/   the one-line image swap, side by side
    azure/  gcp/             multi-cloud quickstarts
  05-act-demo/               README
    run.sh                   the GitHub Actions capstone, run locally with act
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Port 4566 already taken | `floci start --port 4599` then re-run `eval "$(floci env)"` |
| Port 8081 already taken (Module 3) | `ORDER_API_PORT=9090 ./03-real-infra/setup.sh` |
| Module 3 (ECS): `/q/health` is fine but `/orders` hangs | The ECS container can't reach Floci on the host. On Linux, if `host.docker.internal` doesn't resolve inside it: `ORDERS_API_ENDPOINT=http://172.17.0.1:4566 ./03-real-infra/setup.sh` |
| Module 3 (EKS): pods `Running` but `/orders` hangs | Same thing, different address — a pod reaches Floci via the Docker bridge gateway: `K8S_FLOCI_ENDPOINT=http://<gateway-ip>:4566 ./03-real-infra/setup.sh` |
| Module 3 (EKS): pods stuck in `ErrImagePull` | The image isn't in k3s's containerd. Re-run `./03-real-infra/setup.sh`, which imports it |
| Lambda image missing | Re-run `./00-setup/preflight.sh` (pulls `public.ecr.aws/lambda/python:3.12`) |
| S3 errors about addressing | Run `floci doctor --fix` (sets `s3.addressing_style = path`) |
| Testcontainers can't find Docker | On Docker Desktop for macOS: `export DOCKER_HOST=unix://$HOME/.docker/run/docker.sock` before running the tests |
| Wrong image cached | The source of truth is `floci/floci`, not any fork |

---

## License

MIT, free forever.

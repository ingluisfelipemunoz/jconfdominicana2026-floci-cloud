# Build a Whole Cloud Locally with Floci

**Run, test, and ship a real cloud app on your laptop. No account required.**

A 4 hour hands-on workshop. Facilitator runbook.

---

## 1. At a glance

| | |
|---|---|
| Duration | 240 minutes, including one 30 minute break |
| Audience | Intermediate backend and cloud engineers, comfortable with Docker and Java or the AWS CLI |
| Group size | Works from 10 to 60 with one helper per ~15 people |
| What they leave with | A working Quarkus + Lambda event app, a passing integration test suite, a Quarkus API on real ECS plus a real EKS cluster, and a one-command LocalStack migration |
| Primary stack | Floci AWS on port 4566, a Quarkus app on the AWS SDK for Java v2, and a Python Lambda |

### Learning outcomes

By the end, attendees can:

1. Run AWS-shaped services locally with no account, token, or feature gate.
2. Build a real event-driven app: a Quarkus service across S3, SQS, and DynamoDB, with a Python Lambda doing the processing.
3. See where Floci runs real engines instead of mocks, and why that matters.
4. Convert manual setup into isolated, fast Testcontainers integration tests.
5. Stand up real infrastructure locally: deploy a Quarkus API to ECS, and run an EKS cluster.
6. Migrate a LocalStack project to Floci with an image swap, and meet the multi-cloud family.

---

## 2. Before the day: the part that decides everything

Conference wifi will not survive 40 people pulling multi-gigabyte images at once. Treat pre-pull as mandatory, not optional.

### Send one week out

Email attendees the repo link and the preflight script. Ask them to run it on the laptop they will bring and reply if `floci doctor` does not pass.

### Carry a fallback

Put the image tarballs on three or four USB sticks. `docker save` the full image list, hand a stick to anyone whose pull stalls, they `docker load` and rejoin.

### The preflight scripts

[`00-setup/preflight.sh`](00-setup/preflight.sh) checks Docker and the AWS CLI,
installs the Floci CLI if it's missing, pulls every image in
[`00-setup/images.txt`](00-setup/images.txt), and smoke-tests the result with a
real `aws s3 mb`. Every script in the workshop has a PowerShell twin (`.ps1`
alongside each `.sh`) for Windows attendees, including
[`00-setup/floci-env.ps1`](00-setup/floci-env.ps1) — the dot-sourced equivalent
of `eval "$(floci env)"`.

Read the scripts rather than a copy pasted here; an inlined copy drifts.

### `00-setup/images.txt`

Every image the workshop runs lives in that file, including `localstack/localstack`
for the Module 4 comparison and `catthehacker/ubuntu:act-latest` for the Module 5
capstone. If a module pulls an image at demo time, it pulls it over conference
wifi, which is the whole thing preflight exists to prevent.

Use the `latest-compat` tag so the bundled AWS CLI and boto3 are available for init scripts and the migration module.

---

## 3. Repo layout and catch-up scripts

Every module has an idempotent catch-up script. Anyone who falls behind runs one script and rejoins, no manual catch-up. (If you tag the module boundaries in git as well, the tag names below double as checkpoints; the workshop does not depend on it.)

One directory per module, numbered in order.

```
floci-workshop/
  README.md  SOLUTION.md  workshop.md
  00-setup/
    preflight.sh / preflight.ps1 / images.txt
    floci-realdocker.yaml      # socket-mounted compose, for CI or a compose-owned lifecycle
  01-events-core/
    order-cli/                 # the Quarkus S3/SQS/DynamoDB app (pom.xml, src/...)
    lambda/process-order/
      handler.py               # source
      function.zip             # prebuilt, so nobody fights with zipping in the room
    events/sample-order.json
    setup.sh                   # idempotent catch-up
  02-testcontainers/
    java/                      # the Testcontainers suite (Java; other languages linked, not shipped)
  03-real-infra/
    order-api/                 # the Quarkus REST API that ECS runs (pom.xml, Dockerfile, src/...)
    setup.sh                   # ECS + EKS catch-up
  04-migrate-multicloud/
    localstack-before/compose.yaml
    floci-after/compose.yaml
    azure/quickstart.sh
    gcp/quickstart.sh
  05-act-demo/
    .github/workflows/s3-roundtrip.yml   # the workflow, unchanged from what you'd commit
    run.sh                               # runs it locally with act
```

### Catch-up scripts

| Module | Catch-up | State it gets you to |
|---|---|---|
| 0. Setup | (none) | Clean environment verified |
| 1. Event-driven core | `./01-events-core/setup.sh` | Quarkus app + Lambda wired across S3, SQS, DynamoDB |
| 2. CI-grade tests | `cd 02-testcontainers/java && mvn test` | Integration test written and passing |
| 3. Real infra finale | `./03-real-infra/setup.sh` | Quarkus order-api on ECS, serving DynamoDB; EKS cluster running |
| 4. Migrate + multi-cloud | see `04-migrate-multicloud/` | LocalStack swap plus Azure and GCP taste |
| 5. Capstone | `./05-act-demo/run.sh` | GitHub Actions workflow running locally against Floci |

Tell the room the recovery pattern up front: run the module's catch-up script and rejoin, e.g. `./03-real-infra/setup.sh`.

---

## 4. Timeline

| Time | Module | Wow beat |
|---|---|---|
| 0:00 to 0:20 | Setup and first win | AWS in under a minute, no account |
| 0:20 to 1:15 | Event-driven core | A real Quarkus app and a real Lambda container |
| 1:15 to 2:00 | Make it CI-grade | Fresh isolated state per test, fast |
| 2:00 to 2:30 | Break | |
| 2:30 to 3:25 | Real infra finale | A Quarkus API on real ECS serving your orders, then `kubectl get nodes` against EKS |
| 3:25 to 3:45 | Migrate and multi-cloud | One image swap, then the family |
| 3:45 to 3:55 | Capstone | A GitHub Actions workflow, on the laptop, against the local cloud |
| 3:55 to 4:00 | Wrap | Where to go next |

Facilitator tip: keep `floci-ui` projected on the main screen for the whole session. The room watches buckets, tables, and queues appear live as everyone runs commands.

---

## 5. Modules

Each module lists the objective, the steps, the wow beat, common failures, and the catch-up. Every command here has been run against the build in `internal/instructor-guide.md` §1 — but rehearse them end to end on the exact laptop you'll present from anyway, because Docker and CLI versions vary.

---

### Module 0. Setup and first win (20 min)

**Objective:** everyone has a green environment and a fast success.

```bash
floci start
eval "$(floci env)"     # exports AWS_ENDPOINT_URL and dummy credentials
floci doctor            # verifies Docker, ports, socket
```

```bash
aws s3 mb s3://hello
aws dynamodb list-tables
```

**Wow beat:** real AWS CLI output, zero account, in under a minute.

**Common failures:**
- Port 4566 already taken. `floci start --port 4599` then re-run `eval "$(floci env)"`.
- `floci doctor` warns about S3 addressing. Run `floci doctor --fix` to set `s3.addressing_style = path`.

**Catch-up:** none; this is the starting state.

---

### Module 1. Event-driven core with a real app (55 min)

**Objective:** a real Quarkus application places an order into S3 and SQS; a Python Lambda processes the queue and writes to DynamoDB; the app reads it back.

First wire the cloud resources and the Lambda. The room types the five AWS CLI calls by hand (they're step 1 of the [module README](01-events-core/README.md)): create the `orders` bucket, the `order-events` queue, the `orders` DynamoDB table, the `process-order` Lambda from the prebuilt zip, and the SQS → Lambda event source mapping.

Fallback for anyone who mistypes or falls behind — the same five commands, idempotent:

```bash
./01-events-core/setup.sh
```

**The app.** `01-events-core/order-cli/` is a Quarkus command-line app on the AWS SDK for Java v2. Its clients read `AWS_ENDPOINT_URL` and the dummy creds from the environment, so it needs zero Floci-specific code.

```bash
cd 01-events-core/order-cli && mvn -q package && cd -

java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
# -> Placed A-xxxxxxxx -> s3://orders/A-xxxxxxxx.json, queued to order-events

aws s3 ls s3://orders/        # the object the Java app just wrote
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar get A-xxxxxxxx
```

`place` writes the order JSON to S3 and enqueues it to SQS. The Lambda consumes the queue and writes to DynamoDB. `get` reads the processed order back.

**Wow beat:** run `docker ps` mid-module. A real Lambda runtime container is right there processing the queue, while a real Java app you built drives the whole pipeline. This is not a JSON shim pretending.

**Common failures:**
- Lambda image not pre-pulled. Preflight covers `public.ecr.aws/lambda/python:3.12`.
- `get` returns "not found yet" because the Lambda is still working. Wait a second and retry.
- Quarkus build is slow the first time as it resolves dependencies. Have attendees `mvn package` during Module 0 to warm the cache.

**Catch-up:** `./01-events-core/setup.sh`.

---

### Module 2. Make it CI-grade (45 min)

**Objective:** the module that earns adoption at people's jobs. Convert the manual setup into an isolated integration test that spins a fresh Floci per run.

`02-testcontainers/java/pom.xml`:

```xml
<dependency>
  <groupId>io.floci</groupId>
  <artifactId>testcontainers-floci</artifactId>
  <version>1.4.0</version>
  <scope>test</scope>
</dependency>
```

Use `2.5.0` for Testcontainers 2.x and Spring Boot 4.x.

`02-testcontainers/java/.../OrderPipelineTest.java` stands up the **whole Module 1 pipeline** inside one throwaway `FlociContainer`: it creates the bucket, queue, table, and the `process-order` Lambda (from the same `function.zip`), sends an order to SQS, and polls DynamoDB until the Lambda's write lands. Same S3 → SQS → Lambda → DynamoDB flow the attendees just ran by hand, now a single green assertion. The `FlociContainer` mounts the Docker socket itself, which is how it spins the real Lambda runtime; it's pinned to `floci/floci:latest-compat` so CI never pulls an image mid-test.

```bash
cd 02-testcontainers/java && mvn test
```

Run it twice. Each run gets clean, isolated state and starts in a couple of seconds, which is what makes per-job CI practical. (Don't say "milliseconds" on stage — someone will time it; it's ~22s including the real Lambda cold start.)

**Not a Java shop?** Say this out loud — it's the line that makes the module land for the half of the room that doesn't write Java. Testcontainers modules exist for five languages, and they all expose the same shape (`getEndpoint()`, `getRegion()`, `getAccessKey()`, `getSecretKey()`):

| Language | Package |
|---|---|
| Java | `io.floci:testcontainers-floci` |
| Python | `testcontainers-floci` (PyPI) |
| Node.js | `@floci/testcontainers` (npm) |
| Go | `testcontainers-floci-go` |
| .NET | `testcontainers-floci` |

Python, for example, is the same test in six lines:

```python
from floci import FlociContainer
import boto3

def test_pipeline():
    with FlociContainer() as floci:
        s3 = boto3.client("s3", endpoint_url=floci.get_endpoint(),
                          region_name=floci.get_region(),
                          aws_access_key_id=floci.get_access_key(),
                          aws_secret_access_key=floci.get_secret_key())
        s3.create_bucket(Bucket="orders")
```

The workshop ships the Java suite only, so there's one thing to run in the room and nothing to install. Point people at the SDK repos to take it home in their own language.

**Wow beat:** green test suite, fresh state, fast enough to run on the smallest CI runner.

**Catch-up:** `cd 02-testcontainers/java && mvn test`.

---

### Module 3. Real infra finale: ECS and EKS (55 min)

**Objective:** the headline, and the moment the whole arc closes. Deploy a second
Quarkus app — a **web API** — as a real **ECS** container, serving the very orders
the Module 1 CLI placed and the Lambda processed. Then stand up a real Kubernetes
cluster you can `kubectl` at. Both are real containers on the laptop.

```bash
./03-real-infra/setup.sh
```

The script is a full catch-up: it recreates Module 1's pipeline if it's missing,
seeds an order through it, builds the app, runs it on ECS, and creates the EKS
cluster. About 30 seconds from an empty cloud.

**ECS, a real container serving real data.** `03-real-infra/order-api/` is a
Quarkus REST API on the AWS SDK for Java v2. Same `orders` table as Module 1, a
different compute shape: a long-lived container instead of a CLI.

```bash
cd 03-real-infra/order-api && mvn -q package && cd -

# No ECR, no docker push, no registry login. Floci's ECS resolves the image from
# the local Docker daemon, so a plain local tag is all a task definition needs.
docker build -t order-api:1.0 03-real-infra/order-api

aws ecs create-cluster --cluster-name workshop

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

aws ecs run-task --cluster workshop --task-definition order-api \
  --launch-type FARGATE --count 1        # returns once the task is RUNNING

curl http://localhost:8081/orders         # the orders your CLI placed
```

Three things in that task definition are load-bearing, and all three are easy to
get wrong:

| Choice | Why |
|---|---|
| `--network-mode bridge` | `awsvpc` **silently discards your `hostPort`** and gives you a random one instead. Floci's own service docs use `awsvpc` — don't copy them here. |
| An explicit `hostPort` | `0`, or omitting it, also means a random port. |
| No `--requires-compatibilities FARGATE` | It forces `awsvpc`. (`--launch-type FARGATE` on `run-task` is fine and does not.) |

The `AWS_ENDPOINT_URL` line is the **endpoint duality** worth calling out on
stage: the app is a normal AWS SDK app with no Floci-specific code, but a
container Floci spawned reaches the Floci edge back on the *host* — so it needs
`host.docker.internal`, not `localhost`. Floci injects this for Lambda
automatically; for ECS on 1.5.31 you pass it yourself.

**Wow beat — run this live.** Open `http://localhost:8081/` in a browser next to
a terminal. Place an order with the Module 1 CLI, refresh the page, and the new
order appears:

```bash
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
# refresh http://localhost:8081/orders  ->  Grace Hopper is there
```

A Quarkus CLI you built → S3 and SQS → a real Lambda container → DynamoDB → a
Quarkus API you built, running as a real ECS container, serving it back. Five AWS
services, three real engine containers, one laptop, no account. Show `docker ps`
here: `floci-ecs-…`, `floci-…-lambda`, and the edge, all side by side.

**EKS: spin up a real Kubernetes cluster and put the same image on it.**

```bash
aws eks create-cluster --name demo \
  --role-arn arn:aws:iam::000000000000:role/eks \
  --resources-vpc-config subnetIds=subnet-12345

aws eks describe-cluster --name demo --query cluster.status   # poll until ACTIVE

aws eks update-kubeconfig --name demo
kubectl get nodes      # -> a real Ready k3s control-plane node
```

That's a real Kubernetes API server, and `kubectl` is a real `kubectl`. Don't stop
at `get nodes` — **deploy to it.** The same `order-api:1.0` image you just ran on
ECS goes onto the cluster as a two-replica Deployment (`03-real-infra/k8s/order-api.yaml`):

```bash
# k3s has its own containerd and there's no registry to pull from, so hand the
# locally-built image straight to the cluster.
docker save order-api:1.0 | docker exec -i floci-eks-demo ctr -n k8s.io images import -

kubectl apply -f 03-real-infra/k8s/order-api.yaml
kubectl rollout status deployment/order-api

kubectl get nodes
kubectl get pods -l app=order-api      # -> 2 pods, Running
kubectl logs -l app=order-api --tail=5

kubectl port-forward svc/order-api 8082:8080
curl http://localhost:8082/orders      # the same orders, served from Kubernetes
```

Two things in that manifest are worth pointing at on screen:

| Setting | Why |
|---|---|
| `imagePullPolicy: Never` | The image is on the laptop, not in a registry. Without this, Kubernetes tries Docker Hub and you get `ErrImagePull`. |
| `AWS_ENDPOINT_URL: http://172.17.0.1:4566` | The endpoint duality *again*, third variant. A pod can't resolve `host.docker.internal` (the ECS trick), so it reaches Floci through the Docker bridge gateway. The script discovers that IP rather than hardcoding it. |

**Wow beat, part two:** you now have the same image serving from **two different
compute shapes at once** — an ECS container on `:8081` and two Kubernetes pods on
`:8082` — both reading the same DynamoDB table. Place one more order with the CLI
and *both* serve it. That is a genuinely hard thing to demo without a cloud
account, and you just did it on a laptop.

**Resource note:** ECS and EKS together are fine on most laptops; on 8 GB
machines run them one at a time (comment out the EKS block in the script).

**Common failures:**
- **Host port 8081 already taken.** Re-run with `ORDER_API_PORT=9090 ./03-real-infra/setup.sh`.
- **`eclipse-temurin:21-jre` not pulled.** It's the order-api's base image and preflight covers it. Without it, every attendee pulls a JRE mid-module.
- **`/orders` hangs but `/q/health` is fine.** The task can't reach the Floci edge — `AWS_ENDPOINT_URL` is missing or wrong, so the SDK is trying the container's own `localhost`. On Linux, if `host.docker.internal` doesn't resolve inside the task, use the bridge gateway: `ORDERS_API_ENDPOINT=http://172.17.0.1:4566 ./03-real-infra/setup.sh`.
- **`describe-tasks` reports the wrong port.** On 1.5.31 its `networkBindings` echo the *container* port back as the `hostPort` (says 8080 when the real binding is 8081). `docker port` tells the truth. Don't teach attendees to read the port from `describe-tasks`.
- Cluster still creating when they run `kubectl`. Show `describe-cluster` polling first.
- **`ErrImagePull` on the pods.** The image wasn't imported into k3s's containerd, or `imagePullPolicy: Never` is missing. k3s cannot see the host Docker daemon's images.
- **Pods `Running` but `/orders` hangs.** Same endpoint-duality bug as ECS, different address: a pod needs the bridge gateway (`172.17.0.1`), not `host.docker.internal`. Override with `K8S_FLOCI_ENDPOINT=http://<ip>:4566 ./03-real-infra/setup.sh`.
- **NodePort won't reach the cluster.** Floci publishes only the k3s API server (6443), not arbitrary node ports, so use `kubectl port-forward` — which is what the script tells attendees to do.

**Catch-up:** `./03-real-infra/setup.sh`.

---

### Module 4. Migrate and multi-cloud (20 min)

**Objective:** prove the "drop-in" claim, then show the family.

> **Run `floci stop` before this module.** The compose files bind port 4566, the
> same port `floci start` uses — leave Floci up and the container dies with
> `Bind for 0.0.0.0:4566 failed: port is already allocated`.
>
> Stopping Floci **wipes the Modules 0–3 state** (storage is in-memory), so finish
> Module 3 and land its wow beat *first*. Modules 4 and 5 need none of it. To
> restore everything afterwards: `floci start && eval "$(floci env)" && ./03-real-infra/setup.sh`.

**LocalStack swap.** Show `04-migrate-multicloud/localstack-before/compose.yaml` and `04-migrate-multicloud/floci-after/compose.yaml` side by side.

```yaml
# Before
image: localstack/localstack

# After, standard
image: floci/floci:latest

# After, if init scripts need the AWS CLI or boto3
image: floci/floci:latest-compat
```

Environment variables translate automatically:

| LocalStack | Floci |
|---|---|
| `LOCALSTACK_HOST` | `FLOCI_HOSTNAME` |
| `PERSISTENCE=1` | `FLOCI_STORAGE_MODE=persistent` |
| `DEBUG=1` | `QUARKUS_LOG_LEVEL=DEBUG` |

Init scripts mounted under `/etc/localstack/init/` run unchanged, and `/_localstack/health` still answers. Set `LOCALSTACK_PARITY=false` to opt out.

**Azure taste.** `04-migrate-multicloud/azure/quickstart.sh`:

```bash
floci az start
eval "$(floci az env)"   # exports AZURE_STORAGE_CONNECTION_STRING
az storage container create --name my-container
```

**GCP taste.** `04-migrate-multicloud/gcp/quickstart.sh` — **verified working.** It
creates a bucket, uploads an object, lists, and reads it back.

> **It uses `curl`, not `gcloud`, and that's a feature — explain it.** Neither
> `gcloud storage` nor `gsutil` honors `STORAGE_EMULATOR_HOST` any more: both
> ignore the emulator, hit real Google, and 401. That's a **gcloud** problem, not a
> Floci one — the emulator speaks the real GCS JSON API fine, and Google's Python,
> Java and Go client libraries *do* respect the env var and work against it.
> The point for the room: **your application code works; it's the CLI that's
> uncooperative.**
>
> **Azure needs the `az` CLI installed.** The emulator itself is verified (comes up
> on 4577, blob endpoint answers), but the `az` commands are untested — skip the
> Azure taste if you don't have the CLI.

**Wow beat:** the same workflow, one image swap, then the same philosophy across three clouds.

**Catch-up:** `docker compose -f 04-migrate-multicloud/floci-after/compose.yaml up -d`.

---

### Module 5. Capstone: CI locally against the cloud locally (10 min)

**Objective:** the closer. A real GitHub Actions workflow, run on the laptop with
[`act`](https://github.com/nektos/act), doing a full S3 round-trip against Floci.
No GitHub, no AWS account, nothing remote.

> **Floci must be stopped** — the workflow starts its *own* Floci as a service
> container on 4566. If you came straight from Module 4 it already is.

```bash
./05-act-demo/run.sh
```

`05-act-demo/.github/workflows/s3-roundtrip.yml` declares Floci as a **service
container**, so the workflow starts its own cloud, waits for the healthcheck,
creates a bucket, uploads a file, lists, downloads, and `cat`s it. Expected tail:

```
| ----- downloaded.txt -----
| Hello from act + Floci on <timestamp>
| --------------------------
```

**Wow beat:** the file you'd commit to GitHub runs unchanged on your laptop,
against a cloud that also runs unchanged on your laptop.

**Common failures:**
- `act` not installed. It's in the prerequisites; `brew install act`.
- Runner image not pre-pulled. Preflight covers `catthehacker/ubuntu:act-latest`.
- `act` prints a wall of `not located inside a git repository` warnings if the
  repo isn't a git checkout. Harmless, and gone once attendees clone it.
- If the job can't reach Floci at `localhost:4566` on your Docker version, the
  fallback is to address the service by name (`http://floci:4566`) on act's job
  network, and update `AWS_ENDPOINT_URL` in `s3-roundtrip.yml`. This did **not**
  come up on Docker Desktop for macOS in the dry run, but Docker and act versions
  vary, so rehearse it on the laptop you'll present from.

**Catch-up:** `./05-act-demo/run.sh`.

---

### Wrap (5 min)

- Recap the arc: built a real app, ran real engines, tested it, stood up real infra, migrated it.
- Where to go: the docs, GitHub Discussions, and the Slack invite.
- How to contribute, and that it stays MIT and free forever.
- The `solution` tag is the full reference to take home.

---

## 6. Facilitator checklist

**One week out**
- [ ] Repo public, all tags pushed, `solution` verified end to end
- [ ] Preflight script tested on macOS, Windows, and Linux
- [ ] Email sent with repo link and preflight instructions
- [ ] USB sticks loaded with `docker save` tarballs

**Dry run**
- [ ] Every module run end to end on the demo build
- [ ] Quarkus CLI built and run against Floci; `place`/`get` round-trip confirmed
- [ ] `./03-real-infra/setup.sh` confirmed: `curl localhost:8081/orders` serves, `kubectl get nodes` Ready
- [ ] The Module 3 live beat rehearsed: `place` an order, refresh the browser, it appears
- [ ] `./05-act-demo/run.sh` confirmed on the demo laptop
- [ ] Timed each module, trimmed where over
- [ ] `floci-ui` projection tested on the room's display

**At the door**
- [ ] Helpers briefed, one per ~15 attendees
- [ ] Recovery pattern on a slide: run the module's catch-up script, e.g. `./<module-dir>/setup.sh`
- [ ] USB sticks at the front for stalled pulls

**Fallbacks**
- [ ] A known-good finished laptop to mirror for anyone fully blocked
- [ ] A hosted Floci endpoint as a last resort for broken Docker

---

## 7. Swapping the audience

- **Testing or QA conference:** cut Module 3, double Module 2, make per-test isolation and a CI speed comparison the centerpiece.
- **Platform or DevOps:** expand Module 3 — scale the ECS service to several tasks, deploy the same image onto the EKS cluster with `kubectl`, and add a storage-mode tradeoff segment.
- **General backend:** the arc as written, with the Quarkus app as the throughline.
- **OSS-leaning:** add a stretch module on how a service is emulated and how to open a PR to add one.

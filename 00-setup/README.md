# Module 0. Setup and first win

**20 minutes.** Get a green environment, then talk to a cloud that lives entirely
on your laptop.

By the end of this module you'll have run real `aws` CLI commands against real
AWS-shaped services, with no account, no credit card, and no login.

---

## Required tools

Install these **before** you arrive. The preflight script checks all of them.

| Tool | Why | Check |
|---|---|---|
| **Docker** (Desktop or engine) | Floci runs as a container, and spins more containers for Lambda/ECS/EKS | `docker info` |
| **AWS CLI v2** | How you talk to Floci. Used with no real account | `aws --version` |
| **Java 21+** | The Quarkus apps in Modules 1 and 3 | `java -version` |
| **Maven** | Builds those apps and runs the Module 2 tests | `mvn -v` |
| **kubectl** | Module 3 deploys to a real Kubernetes cluster | `kubectl version --client` |
| **[act](https://github.com/nektos/act)** | Module 5 runs GitHub Actions locally (`brew install act`) | `act --version` |
| ~8 GB free disk | The container images | |

You do **not** need an AWS account, a credit card, or any cloud login.

---

## Before the workshop: run the preflight

Conference wifi cannot survive forty people pulling multi-gigabyte images at once.
**Run this at home, on good wifi.**

```bash
./00-setup/preflight.sh          # macOS / Linux
.\00-setup\preflight.ps1         # Windows (PowerShell)
```

It checks your toolchain, installs the Floci CLI, pulls every image the workshop
needs, **builds both Quarkus apps so your Maven cache is warm**, and runs a smoke
test. Expect it to take a while — that is the entire point.

Cold Maven dependency resolution is the slowest thing that can happen to you all
day. Doing it at home is the difference between Module 1 taking five minutes and
taking twenty-five.

---

## Steps

### 1. Start the cloud

```bash
floci start
```

### 2. Point your tools at it

```bash
eval "$(floci env)"              # macOS / Linux
. .\00-setup\floci-env.ps1       # Windows (PowerShell) — note the leading dot
```

This exports `AWS_ENDPOINT_URL` and dummy credentials into your shell. Every AWS
SDK and the AWS CLI read these automatically, which is why **nothing you build
today needs Floci-specific code**.

> Run this in **every new terminal**. It only affects the shell you run it in.
> On Windows the leading `. ` (dot-source) matters — without it the variables
> die with the script.

### 3. Check everything is healthy

```bash
floci doctor
```

Verifies Docker, the ports, and the Docker socket. A warning about S3
path-style addressing is expected and harmless — `floci doctor --fix` clears it.

### 4. Use it like AWS

```bash
aws s3 mb s3://hello
aws s3 ls
aws dynamodb list-tables
```

Real AWS CLI, real responses, zero account, under a minute. **That's the whole
pitch.**

### 5. Warm your build cache while you have a moment

If you skipped the preflight, do this now, before Module 1 needs it:

```bash
cd 01-events-core/order-cli && mvn -q package && cd -
```

---

## What just happened

`floci start` ran the Floci container and published its edge endpoint on port
**4566** — one endpoint that speaks the wire protocol of every AWS service it
emulates, exactly like the real thing. The AWS CLI has no idea it isn't talking to
Amazon.

Where it counts, Floci runs **real engines rather than mocks**: a real Lambda
runtime container, real Kubernetes, real containers for ECS. You'll see them in
`docker ps` as you go.

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot connect to the Docker daemon` | Docker isn't running | Start Docker Desktop, then re-run |
| `port 4566 already allocated` | Something else owns 4566 (often an old LocalStack) | `floci start --port 4599`, then re-run `eval "$(floci env)"` |
| `floci: command not found` after install | The installer added a directory your shell hasn't re-read | Open a new terminal, or `hash -r` |
| `Could not connect to the endpoint URL` | You forgot `eval "$(floci env)"` in this terminal | Run it — it's per-shell |
| `floci doctor` warns `aws.cli.s3.pathstyle` | Custom endpoints need path-style S3 addressing | Harmless. `floci doctor --fix` sets it in `~/.aws/config` |
| S3 commands fail with weird DNS errors | Same path-style issue | `floci doctor --fix` |
| Images pulling slowly at the venue | You skipped the preflight | Grab a USB stick from the front, `docker load` from it |

---

## When you're done: give your laptop back

The workshop leaves behind real containers (a Lambda runtime, an ECS task, a k3s
cluster), a couple of Docker volumes, and about 8 GB of images. One script cleans
all of it up:

```bash
./00-setup/teardown.sh              # containers, volumes, kubeconfig contexts
./00-setup/teardown.sh --images     # the above, plus the ~8 GB of images
```

```powershell
.\00-setup\teardown.ps1             # Windows
.\00-setup\teardown.ps1 -Images     # Windows, images too
```

It only touches what this workshop created (`floci*` containers and volumes, the
`order-api` image, the EKS kubeconfig contexts). Nothing else on your Docker is
affected, and it's safe to re-run.

> Keep the images (run it without `--images`) if you plan to go through the
> workshop again — that's the slow part to re-download.

**Facilitators:** run this between rehearsals. Removing the k3s **volume** matters
— it holds the cluster's node registry, and leaving it behind makes the *next*
cluster come up with a stale second node whose pods hang forever.

---

## Files here

| File | What it is |
|---|---|
| `preflight.sh` / `preflight.ps1` | Run at home: checks tools, pulls images, warms Maven, smoke-tests |
| `teardown.sh` / `teardown.ps1` | Removes everything the workshop created |
| `floci-env.ps1` | Windows twin of `eval "$(floci env)"` — dot-source it in every new terminal |
| `images.txt` | Every image the workshop uses. If a module pulls at demo time, it's a bug — add it here |
| `floci-realdocker.yaml` | A socket-mounted compose file, for CI or when you want compose to own the lifecycle. Not needed for the workshop itself (`floci start` already mounts the socket) |

---

**Next:** [Module 1 — the event-driven core](../01-events-core/README.md)

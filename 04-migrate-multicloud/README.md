# Module 4. Migrate and multi-cloud

**20 minutes.** Two claims, tested.

First: migrating an existing **LocalStack** project to Floci really is a one-line
image swap. Second: the same philosophy extends past AWS — there's an **Azure** and
a **GCP** emulator in the family.

---

## Required tools

| Tool | Why |
|---|---|
| **Docker** + `docker compose` | Both sides of the migration |
| **AWS CLI v2** | To prove the migrated stack works |
| `az` CLI | *Optional* — only for the Azure taste |
| `gcloud` | *Optional* — only for the GCP taste |

---

## Before you start: free port 4566

The compose files here bind **4566** — the same port `floci start` uses. If Floci
is running, the container will not come up:

```
Bind for 0.0.0.0:4566 failed: port is already allocated
```

So begin with:

```bash
floci stop
```

> **This ends your Modules 0–3 state.** Floci's default storage is **in-memory**,
> so stopping it wipes your buckets, queues, tables, and the ECS/EKS deployments.
>
> That's fine — Modules 4 and 5 don't need any of it, and it's the natural end of
> that arc. But **finish Module 3 and take your screenshots first.**
>
> To get it all back afterwards, it's two commands:
> ```bash
> floci start && eval "$(floci env)"
> ./03-real-infra/setup.sh          # rebuilds everything, under a minute
> ```

---

## Part 1: the LocalStack swap

### 1. Look at the "before"

[`localstack-before/compose.yaml`](localstack-before/compose.yaml) — a bog-standard
LocalStack setup: an image, port 4566, three env vars, an init-script mount, and
the Docker socket.

### 2. Look at the "after"

[`floci-after/compose.yaml`](floci-after/compose.yaml).

### 3. Diff them

```bash
diff 04-migrate-multicloud/localstack-before/compose.yaml \
     04-migrate-multicloud/floci-after/compose.yaml
```

**The only functional change is the `image:` line.** Service name, environment
variables, volume mounts — all byte-identical, on purpose.

### 4. Run the migrated stack

```bash
docker compose -f 04-migrate-multicloud/floci-after/compose.yaml up -d
sleep 10        # give it a moment to come up and run the init script

# Floci is no longer managed by the CLI here, so `floci env` can't help.
# Point the AWS CLI at the compose'd container by hand:
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# the init script under ./init ran, unchanged:
aws s3 ls | grep migrated-bucket
#  -> 2026-07-13 11:12:18 migrated-bucket

# even the LocalStack health endpoint still answers:
curl http://localhost:4566/_localstack/health
#  -> {"services":{"s3":"running","sqs":"running","dynamodb":"running",...}}
```

### 5. Tear it down

```bash
docker compose -f 04-migrate-multicloud/floci-after/compose.yaml down -v
```

---

## What makes the swap work

Floci runs a **LocalStack parity mode** (on by default; set
`LOCALSTACK_PARITY=false` to opt out). It honours LocalStack's names so your
existing setup keeps working while you migrate:

- Init scripts mounted at `/etc/localstack/init/ready.d/` run **unchanged**
- `/_localstack/health` still answers
- LocalStack's environment variables are understood

When you're ready to migrate properly, the native spellings are:

| LocalStack | Floci |
|---|---|
| `LOCALSTACK_HOST` | `FLOCI_HOSTNAME` |
| `PERSISTENCE=1` | `FLOCI_STORAGE_MODE=persistent` |
| `DEBUG=1` | `QUARKUS_LOG_LEVEL=DEBUG` |

**Which tag?** Use `floci/floci:latest-compat` if your init scripts need the
bundled AWS CLI or boto3 (the one here does — it calls `awslocal`). Plain
`floci/floci:latest` is fine otherwise.

---

## Part 2: the family

Same idea, different clouds.

### Azure — **needs the `az` CLI installed**

```bash
./04-migrate-multicloud/azure/quickstart.sh        # macOS / Linux
.\04-migrate-multicloud\azure\quickstart.ps1       # Windows (PowerShell)
```

```bash
floci az start
eval "$(floci az env)"      # exports AZURE_STORAGE_CONNECTION_STRING
az storage container create --name my-container
az storage container list --output table
```

The emulator is verified working (it comes up on port 4577 and its blob endpoint
answers). The `az` commands above are **not verified** — the Azure CLI wasn't
installed on the machine this was tested on. If you don't have `az`, skip it.

### GCP — works out of the box

```bash
./04-migrate-multicloud/gcp/quickstart.sh          # macOS / Linux
.\04-migrate-multicloud\gcp\quickstart.ps1         # Windows (PowerShell)
```

It creates a bucket, uploads an object, lists, and reads it back:

```
==> Create a bucket
    created gs://my-bucket
==> Upload an object
    uploaded hello.txt
==> Read the object back
    Hello from Floci GCP
```

> **Why the script uses `curl` and not `gcloud`.** This surprises people, so it's
> worth saying out loud: **neither `gcloud storage` nor `gsutil` honours
> `STORAGE_EMULATOR_HOST` any more.** Both ignore the emulator, go straight to real
> Google, and fail — `401: Login Required` from `gcloud`, and `401 Anonymous caller
> does not have storage.buckets.list access` from `gsutil`. (Verified on gcloud
> 573.)
>
> That's a **gcloud problem, not a Floci one**. The emulator speaks the real GCS
> JSON API perfectly well, so the script drives it the way an SDK would. Google's
> **Python, Java and Go client libraries do respect `STORAGE_EMULATOR_HOST`** and
> work against it directly — which is the point worth making: your *application*
> code works, it's just the CLI that's uncooperative.

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `port is already allocated` on 4566 | `floci start` is already using it | `floci stop`, then bring the compose up |
| The init script didn't run | It has to land at `/etc/localstack/init/ready.d/` | The compose mounts `./init:/etc/localstack/init` because `./init` *already contains* `ready.d/`. **Don't "fix" that mount** — it's correct |
| `awslocal: command not found` in the init script | You're on the plain `latest` tag, which has no bundled AWS CLI | Use `floci/floci:latest-compat` |
| `aws s3 ls` finds nothing after compose up | Your shell still points at the old endpoint, or the container isn't ready | `export AWS_ENDPOINT_URL=http://localhost:4566` and check `curl .../_localstack/health` |
| GCP: `401: Login Required` from `gcloud` | `gcloud storage` ignores `STORAGE_EMULATOR_HOST` and calls real Google | Use the quickstart script — it drives the GCS JSON API with `curl` and works. `gsutil` fails the same way; don't bother |
| Azure: `az: command not found` | The Azure CLI isn't installed | Install it, or skip the Azure taste — nothing else depends on it |
| GCP: port 4588 in use | Something else has it | Change the `-p` mapping and `STORAGE_EMULATOR_HOST` to match |

---

## Cleaning up

Each part of this module starts a container. Stop them when you're done:

```bash
docker compose -f 04-migrate-multicloud/floci-after/compose.yaml down -v
docker rm -f floci-gcp        # if you ran the GCP taste
floci az stop --remove        # if you ran the Azure taste
```

Or just let the teardown script handle all of it:

```bash
./00-setup/teardown.sh
```

---

## Files here

| Path | What it is |
|---|---|
| `localstack-before/compose.yaml` | A typical LocalStack setup |
| `floci-after/compose.yaml` | The same thing, one line changed |
| `*/init/ready.d/01-init.sh` | The init script — **identical on both sides**, which is the point |
| `azure/quickstart.sh` / `.ps1` | Azure blob storage taste |
| `gcp/quickstart.sh` / `.ps1` | GCP bucket taste |

---

## Catch-up

```bash
docker compose -f 04-migrate-multicloud/floci-after/compose.yaml up -d
```

---

**Next:** [Module 5 — the capstone](../05-act-demo/README.md)

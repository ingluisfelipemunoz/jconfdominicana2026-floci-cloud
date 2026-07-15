# Module 1. Event-driven core

**55 minutes.** Build a real event-driven application on five AWS services, all
running on your laptop.

A **Quarkus CLI** places an order into **S3** and **SQS**. A **Python Lambda** —
running in a genuine Lambda runtime container — picks it off the queue and writes
it to **DynamoDB**. Then the CLI reads it back.

This is the heart of the workshop. Everything after it builds on what you make
here.

---

## Required tools

| Tool | Why |
|---|---|
| **Docker**, running | Floci spins a real Lambda container |
| **AWS CLI v2** | Creates the resources |
| **Java 21+ and Maven** | Builds and runs the Quarkus CLI |

**State you need:** Module 0 done — `floci start` is up and you've run
`eval "$(floci env)"` **in this terminal**.

---

## Steps

### 1. Wire up the cloud resources

Five ordinary AWS CLI calls create everything the pipeline needs. Type them —
that's the point:

```bash
# 1. somewhere to put the order document
aws s3 mb s3://orders
```

```bash
# 2. the queue that carries the event
aws sqs create-queue --queue-name order-events
```

```bash
# 3. where the processed order ends up
aws dynamodb create-table \
  --table-name orders \
  --attribute-definitions AttributeName=orderId,AttributeType=S \
  --key-schema AttributeName=orderId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
aws dynamodb wait table-exists --table-name orders
```

```bash
# 4. the Lambda, from the prebuilt zip
aws lambda create-function \
  --function-name process-order \
  --runtime python3.12 \
  --handler handler.handler \
  --role arn:aws:iam::000000000000:role/lambda \
  --zip-file fileb://01-events-core/lambda/process-order/function.zip
```

```bash
# 5. the wiring: SQS triggers the Lambda
aws lambda create-event-source-mapping \
  --function-name process-order \
  --event-source-arn arn:aws:sqs:us-east-1:000000000000:order-events
```

That's five AWS CLI calls against a cloud on your laptop. The `--role` ARN is
accepted but never enforced — there's no IAM to satisfy.

> **Fallback:** in a hurry, hit an error halfway, or fell behind?
> `./01-events-core/setup.sh` (Windows: `.\01-events-core\setup.ps1`) runs these
> exact five commands and is **idempotent** — safe to run again any time, from
> any state.

You can also drive the queue directly with the CLI, skipping the Java app:

```bash
QUEUE=$(aws sqs get-queue-url --queue-name order-events --query QueueUrl --output text)
aws sqs send-message --queue-url "$QUEUE" \
  --message-body file://01-events-core/events/sample-order.json
aws dynamodb scan --table-name orders
```

### 2. Build the app

```bash
cd 01-events-core/order-cli && mvn -q package && cd -
```

First build is slow (Maven downloads Quarkus). If you ran the preflight, it's
already warm.

### 3. Place an order

```bash
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar \
  place --customer "Grace Hopper"
```

```
Placed A-6096aed8 -> s3://orders/A-6096aed8.json, queued to order-events
Read it back once the Lambda runs:  order get A-6096aed8
```

### 4. Prove S3 really has it

```bash
aws s3 ls s3://orders/
```

That object was written by the Java app you just built — not by a script.

### 5. Watch the real Lambda work

```bash
docker ps | grep lambda
```

```
floci-process-order-3d430233   public.ecr.aws/lambda/python:3.12   Up 18 seconds
```

**This is the wow beat.** That is a genuine AWS Lambda runtime container, pulled
from `public.ecr.aws/lambda/python:3.12`, consuming your SQS queue. Not a JSON
shim pretending to be Lambda.

> Give it a second. The container spawns a beat *after* your first `place` — if
> you run `docker ps` instantly you'll see nothing and think it's broken. Once
> it's up it stays warm, so it's there for the rest of the module.

### 6. Read the processed order back

```bash
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar get A-6096aed8
```

The Lambda has to run first. In practice the write lands in **about one to two
seconds** — but if you're quick you'll beat it and see:

```
A-6096aed8 not found yet — the Lambda may still be processing.
```

That is **not a bug**, it's the whole point: this is a genuinely asynchronous
pipeline. Retry once and it's there.

```bash
aws dynamodb scan --table-name orders     # or see it with the CLI
```

---

## What just happened

```
  order-cli  ──put──►  S3  (the order document)
      │
      └──send──►  SQS  ──trigger──►  Lambda  ──put──►  DynamoDB
                                    (real container)        │
  order-cli  ◄──────────────── get ──────────────────────────┘
```

The important part: **nothing in the Java code is Floci-specific.** Look at
`order-cli/src/main/resources/application.properties` — it's a stock AWS SDK v2
setup reading `AWS_ENDPOINT_URL` and credentials from the environment. Those are
the same knobs you'd use to point a real app at any non-default endpoint.

Take the environment variables away and this app talks to real AWS.

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot reach an AWS endpoint` from `setup.sh` | Floci isn't up, or this shell has no env | `floci start && eval "$(floci env)"` |
| `get` says the order isn't there | The Lambda is still working — it's asynchronous | Wait a second and retry. It normally lands in 2–4s |
| `get` **never** finds it | The Lambda isn't firing. Usually the event source mapping | Re-run `./01-events-core/setup.sh`, then `docker ps \| grep lambda` |
| Lambda container never appears | `public.ecr.aws/lambda/python:3.12` wasn't pre-pulled | Re-run `./00-setup/preflight.sh` |
| `mvn package` takes forever | Cold Maven cache, first Quarkus build | Expected once. This is what the preflight prevents |
| `Unable to access jarfile` | You're not in the repo root, or you haven't built yet | Run `mvn -q package` in `01-events-core/order-cli` first |
| The `items` field prints as `AttributeValue(...)` | Expected — it's showing the nested DynamoDB structure | Not a bug |
| `NoSuchBucket` / `ResourceNotFoundException` | Resources were never created, or Floci restarted (storage is in-memory) | Re-run `./01-events-core/setup.sh` |

> **Floci's default storage is in-memory.** Restart Floci and your buckets, queues
> and tables are gone. Re-run the setup script and you're back — that's what it's
> for.

---

## Files here

| Path | What it is |
|---|---|
| `order-cli/` | The Quarkus CLI. Has its own [README](order-cli/README.md) |
| `lambda/process-order/handler.py` | The Lambda source — 30 lines of boto3 |
| `lambda/process-order/function.zip` | Prebuilt, so nobody fights with zipping in the room |
| `events/sample-order.json` | A sample order document |
| `setup.sh` | Idempotent catch-up |

---

## Catch-up

Fell behind? This recreates everything:

```bash
./01-events-core/setup.sh          # macOS / Linux
.\01-events-core\setup.ps1         # Windows (PowerShell)
```

---

**Next:** [Module 2 — make it CI-grade](../02-testcontainers/README.md)

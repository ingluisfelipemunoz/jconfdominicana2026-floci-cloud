# Module 2. Make it CI-grade

**45 minutes.** This is the module that earns adoption at your job.

Turn the manual setup from Module 1 into an **isolated integration test** that
spins up a fresh cloud per run, drives an order all the way through the pipeline,
and asserts the Lambda's write. Fresh state every time, no shared account, no
leftover data, fast enough to run on the smallest CI runner.

---

## Required tools

| Tool | Why |
|---|---|
| **Docker**, running | Testcontainers starts Floci, and Floci starts a real Lambda |
| **Java 21+ and Maven** | The test suite |

**State you need:** none. That's the point — the test builds its own cloud from
nothing. You don't even need `floci start` running.

---

## Steps

### 1. Run it

```bash
cd 02-testcontainers/java
mvn test
```

```
Tests run: 1, Failures: 0, Errors: 0
BUILD SUCCESS
```

Takes about 22 seconds, most of which is the real Lambda cold-starting.

> Run it **from inside `02-testcontainers/java`**. The test locates
> `function.zip` by a relative path.

### 2. Run it again

```bash
mvn test
```

Green again — from completely fresh state. No cleanup, no `@BeforeEach` deleting
rows, no "who left data in the shared dev account" archaeology.

**That is the whole argument.** Per-job CI against a real cloud becomes practical.

### 3. Read the test

Open [`src/test/java/io/floci/workshop/OrderPipelineTest.java`](java/src/test/java/io/floci/workshop/OrderPipelineTest.java).

It stands up the **entire Module 1 pipeline** inside one throwaway container:

1. Creates the bucket, queue, and table
2. Deploys the `process-order` Lambda from the *same* `function.zip` you used in Module 1
3. Wires the SQS → Lambda event source mapping
4. Puts an order in S3 and sends it to SQS
5. Polls DynamoDB until the Lambda's write lands

Same S3 → SQS → Lambda → DynamoDB flow you ran by hand, now one green assertion.

---

## What just happened

```java
@Container
static FlociContainer floci = new FlociContainer("floci/floci:latest-compat");
```

That single line gives every test class its own private cloud. `FlociContainer`
mounts the Docker socket itself, which is how it can spin the **real Lambda
runtime** inside the test.

The image tag is **pinned** on purpose: CI should never pull a floating `latest`
in the middle of a test run.

Then the SDK clients are built from the container's own coordinates, so nothing is
hardcoded and parallel test classes can't collide:

```java
builder.endpointOverride(URI.create(floci.getEndpoint()))
       .region(Region.of(floci.getRegion()))
       .credentialsProvider(/* floci.getAccessKey(), floci.getSecretKey() */);
```

Don't say "milliseconds" when you show this off — someone will time it. It's
seconds, and seconds is already transformative compared to a shared cloud account.

---

## Testing in your language

The suite here is Java so there's one thing to run in the room, but the
Testcontainers module is not Java-only. Every one of them exposes the same shape —
`getEndpoint()`, `getRegion()`, `getAccessKey()`, `getSecretKey()` — so this test
ports across directly.

| Language | Package |
|---|---|
| Java | `io.floci:testcontainers-floci` |
| Python | `testcontainers-floci` (PyPI) |
| Node.js | `@floci/testcontainers` (npm) |
| Go | `testcontainers-floci-go` |
| .NET | `testcontainers-floci` |

The same test in Python is six lines:

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

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `Could not find a valid Docker environment` | Testcontainers can't find the Docker socket | On Docker Desktop for macOS: `export DOCKER_HOST=unix://$HOME/.docker/run/docker.sock` |
| `NoSuchFileException: ../../01-events-core/.../function.zip` | You ran Maven from the wrong directory | `cd 02-testcontainers/java` first |
| The test hangs, then fails waiting for DynamoDB | The Lambda never ran — usually its image isn't present | Pre-pull it: `docker pull public.ecr.aws/lambda/python:3.12` |
| First run is slow / pulls an image | `floci/floci:latest-compat` wasn't pre-pulled | Re-run `./00-setup/preflight.sh` |
| Test passes alone but fails in a suite | Port or state collision | It shouldn't — each class gets its own container. File a bug with the log |
| Docker runs out of memory | Real Lambda containers add up | `docker system prune`, and give Docker Desktop more RAM |

---

## Catch-up

```bash
cd 02-testcontainers/java && mvn test
```

---

**Next:** [Module 3 — the real infra finale](../03-real-infra/README.md)

# Build a Whole Cloud Locally with Floci

**A 4-hour hands-on workshop. Run, test, and ship a real cloud app on your laptop, with no account, no token, and nothing remote.**

---

## Abstract

Cloud development usually means an account, credentials, billing, and a slow
round-trip to someone else's data center just to test a five-line change.
[Floci](https://floci.io) runs AWS-shaped services right on your laptop. Where it
counts, it runs the *real* engines instead of mocks: a real Lambda runtime, real
Kubernetes, real containers.

In this workshop you'll build a genuine event-driven application. It's a Quarkus
service and a Python Lambda working together across S3, SQS, and DynamoDB, all on
your own machine. From there you'll make it CI-grade with isolated integration
tests, stand up real infrastructure — deploying a Quarkus web API as a real ECS
container and running a Kubernetes cluster you talk to with `kubectl` — migrate a
LocalStack project with a one-line image swap, and finish by running a GitHub
Actions pipeline locally against your local cloud.

---

## What you'll build

- An **event-driven app**: a Quarkus CLI (AWS SDK for Java v2) that places orders
  into **S3** and **SQS**, a **Python Lambda** that processes the queue into
  **DynamoDB**, and a command that reads the result back.
- A **CI-grade test suite** with Testcontainers. Every test gets fresh, isolated
  cloud state, fast enough for the smallest runner.
- **Real infrastructure**, locally: a second Quarkus app — a web API — deployed
  *twice* from one image. Once as a real **ECS** container, and once as a
  Deployment on a real **EKS** Kubernetes cluster you drive with `kubectl`. Both
  serve the orders your pipeline produced, at the same time.
- A **LocalStack to Floci migration** that really is a one-line image swap.
- A capstone: a **GitHub Actions workflow run on your laptop with `act`** that
  does a full S3 round-trip against Floci. CI locally, cloud locally.

## You'll leave able to

1. Run AWS-shaped services locally with no account, token, or feature gate.
2. Build and debug an event-driven pipeline across S3, SQS, Lambda, and DynamoDB.
3. Spot where Floci runs real engines instead of mocks, and know why that matters.
4. Turn manual setup into fast, isolated Testcontainers integration tests.
5. Stand up real infrastructure (ECS, EKS) on your own machine.
6. Migrate an existing LocalStack project to Floci.

---

## Who it's for

Intermediate backend and cloud engineers who are comfortable with Docker and
either Java or the AWS CLI. No prior Floci experience needed.

## Prerequisites (install before you arrive)

- **Docker** (Desktop or engine), running
- **Java 21+** and **Maven**
- **AWS CLI v2**
- **`kubectl`** and **[`act`](https://github.com/nektos/act)**
- About 8 GB of free disk for container images

---

## Before you arrive

You'll get the workshop repository link and a one-command preflight script about
a week before the session. Conference wifi can't survive everyone pulling
multi-gigabyte images at once, so please run the preflight at home on good wifi.
It installs the Floci CLI, pulls the images, and smoke-tests your setup.

For now, just make sure the prerequisites above are installed on the laptop
you'll bring.

---

## The session at a glance

| # | Module | Time | What you do |
|---|--------|------|-------------|
| 0 | Setup and first win | 20 min | `floci start`, then real AWS CLI output in under a minute |
| 1 | Event-driven core | 55 min | Build and run the Quarkus app, then watch the Lambda process orders into DynamoDB |
| 2 | Make it CI-grade | 45 min | Write a Testcontainers test with fresh isolated state per run |
|   | Break | 30 min | |
| 3 | Real infra finale | 55 min | Deploy your Quarkus API to real ECS, then to a real Kubernetes cluster — one image, two compute shapes |
| 4 | Migrate and multi-cloud | 20 min | Swap LocalStack for Floci, plus a taste of Azure and GCP |
| 5 | Capstone | 10 min | Run a GitHub Actions workflow locally with `act` against Floci |
|   | Wrap | 5 min | Where to go next |

Each module is a git checkpoint. If you fall behind, run one idempotent script
and rejoin at the next step.

---

## Format

Four hours, including one 30-minute break. It works for 10 to 60 attendees with
one helper per 15 people or so. Everything is MIT-licensed and free forever, and
you take the whole repo home.

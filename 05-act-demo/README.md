# Module 5. Capstone: CI locally, against the cloud locally

**10 minutes.** The closer.

A real **GitHub Actions workflow**, running on your laptop with
[`act`](https://github.com/nektos/act), doing a full **S3 round-trip** against
Floci. No GitHub. No AWS account. Nothing remote, at all.

---

## Required tools

| Tool | Why |
|---|---|
| **Docker**, running | `act` runs the job in a container, and Floci runs as a service container |
| **[act](https://github.com/nektos/act)** | Runs the workflow locally (`brew install act`) |

**State you need:** none. **You don't even need Floci running** — the workflow
starts its own cloud, as a service container.

---

## Steps

### 1. Make sure port 4566 is free

The workflow runs Floci as a **service container** on port 4566. If you still have
`floci start` running from the earlier modules, it owns that port and the service
container can't bind it.

```bash
floci stop
```

(If you did Module 4, Floci is already stopped and there's nothing to do.)

> Stopping Floci wipes the in-memory state from Modules 0–3. That's fine here —
> this module needs none of it. To bring it all back afterwards:
> `floci start && eval "$(floci env)" && ./03-real-infra/setup.sh`

### 2. Run it

```bash
./05-act-demo/run.sh               # macOS / Linux
.\05-act-demo\run.ps1              # Windows (PowerShell)
```

The script pre-pulls the runner image, points `act` at the right Docker socket,
and on Apple Silicon adds `--container-architecture linux/amd64` (the
`catthehacker` runner images are amd64-only).

### 3. Watch the workflow

It creates a bucket, uploads a file, lists the bucket, downloads it, and `cat`s
it. Expected tail:

```
| ----- downloaded.txt -----
| Hello from act + Floci on <timestamp>
| --------------------------
```

### 4. Read the workflow

Open [`.github/workflows/s3-roundtrip.yml`](.github/workflows/s3-roundtrip.yml).

**This is a file you would commit to GitHub unchanged.** No local-only hack, no
`if: github.actor == 'act'` escape hatch. Nothing.

---

## What just happened

The trick is one block:

```yaml
services:
  floci:
    image: floci/floci:latest-compat
    ports:
      - 4566:4566
```

Floci runs as a **service container declared by the job itself**, so the workflow
is fully self-contained: it starts its own cloud, waits for the healthcheck, does
the round-trip, and tears everything down.

`act` runs the job on the host network, so it reaches Floci at
`http://localhost:4566` — which is *exactly* how GitHub-hosted runners expose
service containers. That's why the same file works in both places.

One AWS quirk: S3 against a custom endpoint needs **path-style** addressing (no
bucket-as-subdomain), so the first step writes `~/.aws/config` with
`addressing_style = path`.

---

## The point

The file you'd commit to GitHub runs unchanged on your laptop, against a cloud
that also runs unchanged on your laptop.

Which means you can debug a CI pipeline **without pushing a commit** — no more
`fix ci`, `fix ci again`, `please work` in your git history.

---

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `act: command not found` | Not installed | `brew install act` |
| A wall of `not located inside a git repository` warnings | The repo isn't a git checkout | **Harmless.** Gone once you `git clone` it |
| `exec format error`, or the runner image won't start | Apple Silicon + an amd64 runner image | `run.sh` handles it with `--container-architecture linux/amd64` |
| `Cannot connect to the Docker daemon` | `act` looked in the wrong place for the socket | `run.sh` sets `DOCKER_HOST` from your active Docker context. If it still fails: `export DOCKER_HOST=unix://$HOME/.docker/run/docker.sock` |
| It pulls a ~1 GB runner image | `catthehacker/ubuntu:act-latest` wasn't pre-pulled | Re-run `./00-setup/preflight.sh` |
| `Floci did not become ready` | The service container didn't come up in 60s | Give Docker more memory, then re-run |
| `port is already allocated` on 4566 | You have `floci start` running | `floci stop` — the workflow brings its own cloud |
| The job can't reach `localhost:4566` | Your Docker/act version doesn't give the job host networking | Address the service **by name** instead: set `AWS_ENDPOINT_URL: http://floci:4566` in the workflow. `act` puts service containers on the job's network under a service-name alias |

---

## Files here

| Path | What it is |
|---|---|
| `.github/workflows/s3-roundtrip.yml` | The workflow — unchanged from what you'd commit |
| `run.sh` / `run.ps1` | Runs it locally with `act` |

---

## Catch-up

```bash
./05-act-demo/run.sh
```

---

**That's the workshop.** Back to the [main README](../README.md).

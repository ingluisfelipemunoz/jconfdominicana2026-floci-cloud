# Solution reference

The finished state of every module, end to end. If you get stuck, the `setup.sh`
in each module directory recreates that state idempotently.

```bash
./<module-dir>/setup.sh
```

---

## Module 0. Setup

```bash
floci start
eval "$(floci env)"
floci doctor
aws s3 mb s3://hello
aws dynamodb list-tables
```

---

## Module 1. Event-driven core

`./01-events-core/setup.sh` wires the cloud resources and the Lambda. By hand:

```bash
aws s3 mb s3://orders
aws sqs create-queue --queue-name order-events

aws dynamodb create-table \
  --table-name orders \
  --attribute-definitions AttributeName=orderId,AttributeType=S \
  --key-schema AttributeName=orderId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

aws lambda create-function \
  --function-name process-order \
  --runtime python3.12 \
  --handler handler.handler \
  --role arn:aws:iam::000000000000:role/lambda \
  --zip-file fileb://01-events-core/lambda/process-order/function.zip

aws lambda create-event-source-mapping \
  --function-name process-order \
  --event-source-arn arn:aws:sqs:us-east-1:000000000000:order-events
```

Then drive it with the **Quarkus app**:

```bash
cd 01-events-core/order-cli && mvn -q package && cd -

java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
# -> Placed A-xxxxxxxx -> s3://orders/A-xxxxxxxx.json, queued to order-events

aws s3 ls s3://orders/                       # the object the app wrote
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar get A-xxxxxxxx
```

`docker ps` shows the real Lambda runtime container while it processes.

---

## Module 2. CI-grade tests

```bash
cd 02-testcontainers/java && mvn -q test
```

Run it twice. Fresh isolated state every run, fast enough for the smallest CI
runner.

The suite here is Java, but the Testcontainers module exists for Java, Python,
Node.js, Go, and .NET — all with the same `getEndpoint()` / `getRegion()` /
`getAccessKey()` / `getSecretKey()` shape, so this test ports straight across.

---

## Module 3. Real infra finale: ECS and EKS

`./03-real-infra/setup.sh` does both, and recreates Module 1's pipeline first if
it's missing. By hand:

**ECS (the Quarkus order-api as a real container):**

```bash
cd 03-real-infra/order-api && mvn -q package && cd -

# No ECR, no push, no registry login: Floci's ECS resolves the image from the
# local Docker daemon, so a plain local tag is all the task definition needs.
docker build -t order-api:1.0 03-real-infra/order-api

aws ecs create-cluster --cluster-name workshop

# network-mode MUST be bridge and hostPort MUST be explicit — awsvpc (and
# --requires-compatibilities FARGATE, which forces it) discards the hostPort and
# gives you a random one instead.
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
      {"name": "AWS_ENDPOINT_URL",      "value": "http://host.docker.internal:4566"},
      {"name": "AWS_REGION",            "value": "us-east-1"},
      {"name": "AWS_ACCESS_KEY_ID",     "value": "test"},
      {"name": "AWS_SECRET_ACCESS_KEY", "value": "test"}
    ]
  }]'

aws ecs run-task --cluster workshop --task-definition order-api \
  --launch-type FARGATE --count 1        # returns once the task is RUNNING

curl http://localhost:8081/q/health       # {"status":"UP"}
curl http://localhost:8081/orders         # the orders the CLI placed + the Lambda wrote
docker ps | grep floci-ecs                # the real container behind it
```

Then close the loop live — place an order and watch it appear in the API:

```bash
java -jar 01-events-core/order-cli/target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
curl http://localhost:8081/orders         # Grace Hopper is now there
```

**EKS (real Kubernetes via k3s), and the same image deployed onto it:**

```bash
aws eks create-cluster --name demo \
  --role-arn arn:aws:iam::000000000000:role/eks \
  --resources-vpc-config subnetIds=subnet-12345

until [ "$(aws eks describe-cluster --name demo --query cluster.status --output text)" = ACTIVE ]; do sleep 5; done

aws eks update-kubeconfig --name demo
kubectl get nodes      # -> a real Ready k3s control-plane node

# k3s has its own containerd and no registry to pull from: hand it the image.
docker save order-api:1.0 | docker exec -i floci-eks-demo ctr -n k8s.io images import -

kubectl apply -f 03-real-infra/k8s/order-api.yaml
kubectl rollout status deployment/order-api
kubectl get pods -l app=order-api       # -> 2 pods, Running

kubectl port-forward svc/order-api 8082:8080
curl http://localhost:8082/orders       # the same orders, now served from Kubernetes
```

The manifest needs `imagePullPolicy: Never` (the image is local, not in a
registry) and points `AWS_ENDPOINT_URL` at the Docker bridge gateway
(`http://172.17.0.1:4566`) — a pod can't resolve `host.docker.internal` the way
an ECS task can.

**The finale:** the same image is now serving from two compute shapes at once —
an ECS container on `:8081` and two Kubernetes pods on `:8082` — both reading the
same DynamoDB table. Place another order and both serve it.

---

## Module 4. Migrate and multi-cloud

LocalStack swap, side by side:

```bash
docker compose -f 04-migrate-multicloud/localstack-before/compose.yaml up -d   # before
docker compose -f 04-migrate-multicloud/floci-after/compose.yaml up -d         # after, one line changed
```

Family taste:

```bash
./04-migrate-multicloud/azure/quickstart.sh
./04-migrate-multicloud/gcp/quickstart.sh
```

---

## Module 5. Capstone: `act` + Floci

A real GitHub Actions workflow, run locally, against a locally running S3:

```bash
./05-act-demo/run.sh
```

The workflow starts Floci as a service container, so nothing has to be running
on the host first. Expected tail:

```
| ----- downloaded.txt -----
| Hello from act + Floci on <timestamp>
| --------------------------
```

# order-cli

A real Quarkus command-line app, built on the AWS SDK for Java v2, that drives
the order pipeline against Floci:

- **`place`** builds an order, uploads it to **S3**, and drops it on **SQS**.
- **`get <orderId>`** reads the processed order back from **DynamoDB**. (The
  Python Lambda in `../lambda/process-order/` is what moves it from SQS into
  DynamoDB.)

## Build

```bash
mvn -q package
```

Produces a fast-jar at `target/quarkus-app/quarkus-run.jar`.

## Run

The clients read their endpoint and credentials from the environment, so make
sure Floci is up first:

```bash
floci start
eval "$(floci env)"
../setup.sh                            # create bucket, queue, table, Lambda

java -jar target/quarkus-app/quarkus-run.jar place --customer "Grace Hopper"
# -> Placed A-1a2b3c4d -> s3://orders/A-1a2b3c4d.json, queued to order-events

java -jar target/quarkus-app/quarkus-run.jar get A-1a2b3c4d
# -> the order, after the Lambda has processed it
```

### Dev mode

```bash
mvn quarkus:dev -Dquarkus.args='place --customer "Ada Lovelace"'
```

## How it points at Floci

`src/main/resources/application.properties` configures the S3, SQS, and DynamoDB
clients with `endpoint-override=${AWS_ENDPOINT_URL:...}`, static dummy
credentials, and S3 path-style access. These are the same knobs you'd flip to
point a real app at any non-default endpoint, so nothing in the Java code is
Floci-specific.

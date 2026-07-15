package io.floci.workshop;

import static java.nio.charset.StandardCharsets.UTF_8;
import static java.util.concurrent.TimeUnit.SECONDS;
import static org.awaitility.Awaitility.await;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.floci.testcontainers.FlociContainer;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeDefinition;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.BillingMode;
import software.amazon.awssdk.services.dynamodb.model.KeySchemaElement;
import software.amazon.awssdk.services.dynamodb.model.KeyType;
import software.amazon.awssdk.services.dynamodb.model.ScalarAttributeType;
import software.amazon.awssdk.services.lambda.LambdaClient;
import software.amazon.awssdk.services.lambda.model.Runtime;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.QueueAttributeName;

/**
 * The whole Module 1 pipeline — S3 -> SQS -> Lambda -> DynamoDB — inside a
 * single, throwaway Floci. Each run stands the pipeline up from nothing, drives
 * one order through it, and asserts the Lambda's DynamoDB write. That is the
 * argument for per-job CI: fresh isolated cloud state in a couple of seconds,
 * no shared account, no leftover data. Run it twice and watch it stay green.
 */
@Testcontainers
class OrderPipelineTest {

    // Pin the pre-pulled -compat image so CI (and the workshop room) never pulls
    // floci/floci:latest over the network mid-test. FlociContainer mounts the
    // Docker socket itself, which is what lets it spin the real Lambda runtime.
    @Container
    static FlociContainer floci = new FlociContainer("floci/floci:latest-compat");

    private static final String BUCKET = "orders";
    private static final String QUEUE = "order-events";
    private static final String TABLE = "orders";
    private static final String FUNCTION = "process-order";
    private static final String ACCOUNT = "000000000000";
    private static final Path FUNCTION_ZIP =
            Path.of("..", "..", "01-events-core", "lambda", "process-order", "function.zip");

    private <T extends software.amazon.awssdk.awscore.client.builder.AwsClientBuilder<T, ?>>
            T configure(T builder) {
        return builder
                .endpointOverride(URI.create(floci.getEndpoint()))
                .region(Region.of(floci.getRegion()))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(floci.getAccessKey(), floci.getSecretKey())));
    }

    @Test
    void orderFlowsFromSqsThroughLambdaToDynamo() throws Exception {
        S3Client s3 = configure(S3Client.builder())
                .httpClient(UrlConnectionHttpClient.create())
                .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(true).build())
                .build();
        SqsClient sqs = configure(SqsClient.builder())
                .httpClient(UrlConnectionHttpClient.create()).build();
        LambdaClient lambda = configure(LambdaClient.builder())
                .httpClient(UrlConnectionHttpClient.create()).build();
        DynamoDbClient dynamo = configure(DynamoDbClient.builder())
                .httpClient(UrlConnectionHttpClient.create()).build();

        // --- stand the pipeline up, exactly what 01-events-core/setup.sh does ---
        s3.createBucket(b -> b.bucket(BUCKET));
        sqs.createQueue(b -> b.queueName(QUEUE));
        String queueUrl = sqs.getQueueUrl(b -> b.queueName(QUEUE)).queueUrl();
        String queueArn = sqs.getQueueAttributes(b -> b
                        .queueUrl(queueUrl)
                        .attributeNames(QueueAttributeName.QUEUE_ARN))
                .attributes().get(QueueAttributeName.QUEUE_ARN);

        dynamo.createTable(b -> b
                .tableName(TABLE)
                .billingMode(BillingMode.PAY_PER_REQUEST)
                .attributeDefinitions(AttributeDefinition.builder()
                        .attributeName("orderId").attributeType(ScalarAttributeType.S).build())
                .keySchema(KeySchemaElement.builder()
                        .attributeName("orderId").keyType(KeyType.HASH).build()));
        dynamo.waiter().waitUntilTableExists(r -> r.tableName(TABLE));

        SdkBytes functionZip = SdkBytes.fromByteArray(Files.readAllBytes(FUNCTION_ZIP));
        lambda.createFunction(b -> b
                .functionName(FUNCTION)
                .runtime(Runtime.PYTHON3_12)
                .handler("handler.handler")
                .role("arn:aws:iam::" + ACCOUNT + ":role/lambda")
                .code(c -> c.zipFile(functionZip)));
        lambda.createEventSourceMapping(b -> b
                .functionName(FUNCTION)
                .eventSourceArn(queueArn));

        // --- drive one order through it, like the Quarkus `place` command ---
        String orderId = "A-1001";
        String orderJson = """
                {"orderId":"%s","customer":"Ada Lovelace","total":68.98,"status":"received"}"""
                .formatted(orderId);

        s3.putObject(b -> b.bucket(BUCKET).key(orderId + ".json"),
                RequestBody.fromString(orderJson, UTF_8));
        sqs.sendMessage(b -> b.queueUrl(queueUrl).messageBody(orderJson));

        // --- the Lambda processes asynchronously; poll DynamoDB for its write ---
        await().atMost(Duration.ofSeconds(60)).pollInterval(Duration.ofSeconds(1)).untilAsserted(() -> {
            Map<String, AttributeValue> item = dynamo.getItem(b -> b
                    .tableName(TABLE)
                    .key(Map.of("orderId", AttributeValue.fromS(orderId)))).item();
            assertEquals("Ada Lovelace", item.getOrDefault("customer", AttributeValue.fromS("")).s(),
                    "the Lambda should have written the order to DynamoDB");
        });
    }
}

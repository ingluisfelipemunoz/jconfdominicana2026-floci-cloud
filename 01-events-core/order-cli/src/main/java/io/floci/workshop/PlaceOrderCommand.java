package io.floci.workshop;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.inject.Inject;
import java.util.List;
import java.util.UUID;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.sqs.SqsClient;

/** Build an order, store it in S3, and enqueue it to SQS for the Lambda. */
@Command(name = "place", description = "Place an order: upload to S3 and enqueue to SQS")
public class PlaceOrderCommand implements Runnable {

    @Option(names = {"-c", "--customer"}, defaultValue = "Ada Lovelace",
            description = "Customer name")
    String customer;

    @Option(names = "--bucket", defaultValue = "orders", description = "S3 bucket")
    String bucket;

    @Option(names = "--queue", defaultValue = "order-events", description = "SQS queue name")
    String queueName;

    private final S3Client s3;
    private final SqsClient sqs;
    private final ObjectMapper mapper;

    @Inject
    public PlaceOrderCommand(S3Client s3, SqsClient sqs, ObjectMapper mapper) {
        this.s3 = s3;
        this.sqs = sqs;
        this.mapper = mapper;
    }

    @Override
    public void run() {
        String orderId = "A-" + UUID.randomUUID().toString().substring(0, 8);
        List<Order.Item> items = List.of(
                new Order.Item("WIDGET-1", 2, 9.99),
                new Order.Item("GADGET-7", 1, 49.0));
        double total = items.stream().mapToDouble(i -> i.qty() * i.price()).sum();

        Order order = new Order(orderId, customer, total, "received", items);

        try {
            String json = mapper.writeValueAsString(order);

            s3.putObject(PutObjectRequest.builder().bucket(bucket).key(orderId + ".json").build(),
                    RequestBody.fromString(json));

            String queueUrl = sqs.getQueueUrl(b -> b.queueName(queueName)).queueUrl();
            sqs.sendMessage(b -> b.queueUrl(queueUrl).messageBody(json));

            System.out.printf("Placed %s -> s3://%s/%s.json, queued to %s%n",
                    orderId, bucket, orderId, queueName);
            System.out.printf("Read it back once the Lambda runs:  order get %s%n", orderId);
        } catch (Exception e) {
            throw new RuntimeException("Failed to place order " + orderId, e);
        }
    }
}

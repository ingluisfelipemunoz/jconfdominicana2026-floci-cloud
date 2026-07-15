package io.floci.workshop;

import jakarta.inject.Inject;
import java.util.Map;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import picocli.CommandLine.Parameters;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;

/** Read an order the Lambda wrote to DynamoDB. */
@Command(name = "get", description = "Read a processed order back from DynamoDB")
public class GetOrderCommand implements Runnable {

    @Parameters(index = "0", description = "Order id, e.g. A-1a2b3c4d")
    String orderId;

    @Option(names = "--table", defaultValue = "orders", description = "DynamoDB table")
    String table;

    private final DynamoDbClient db;

    @Inject
    public GetOrderCommand(DynamoDbClient db) {
        this.db = db;
    }

    @Override
    public void run() {
        Map<String, AttributeValue> item = db.getItem(b -> b
                .tableName(table)
                .key(Map.of("orderId", AttributeValue.fromS(orderId)))).item();

        if (item == null || item.isEmpty()) {
            System.out.printf("Order %s not found yet — the Lambda may still be processing.%n", orderId);
            return;
        }

        System.out.printf("Order %s:%n", orderId);
        item.forEach((k, v) -> System.out.printf("  %-10s %s%n", k, render(v)));
    }

    private static String render(AttributeValue v) {
        if (v.s() != null) return v.s();
        if (v.n() != null) return v.n();
        return v.toString();
    }
}

package io.floci.workshop;

import java.util.List;

/** The order document the CLI writes to S3 and enqueues to SQS. */
public record Order(
        String orderId,
        String customer,
        double total,
        String status,
        List<Item> items) {

    public record Item(String sku, int qty, double price) {}
}

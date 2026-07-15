package io.floci.workshop;

import io.quarkus.picocli.runtime.annotations.TopCommand;
import picocli.CommandLine.Command;

/**
 * Floci workshop order CLI. A real Quarkus app driving S3, SQS, and DynamoDB
 * against the local Floci endpoint.
 *
 *   place           upload an order to S3 and enqueue it to SQS
 *   get <orderId>   read the processed order back from DynamoDB
 */
@TopCommand
@Command(
        name = "order",
        mixinStandardHelpOptions = true,
        subcommands = {PlaceOrderCommand.class, GetOrderCommand.class},
        description = "Floci workshop order CLI (S3 + SQS + DynamoDB)")
public class OrderCli {
}

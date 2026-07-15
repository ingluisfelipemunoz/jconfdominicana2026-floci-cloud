package io.floci.workshop.api;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;

/**
 * A real Quarkus web API, running as an ECS container on Floci, that serves the
 * orders the Module 1 CLI placed and the Lambda wrote to DynamoDB. Same table,
 * a different compute shape — a long-lived container instead of a CLI.
 */
@Path("/orders")
@Produces(MediaType.APPLICATION_JSON)
public class OrdersResource {

    private final DynamoDbClient db;
    private final String table;

    @Inject
    public OrdersResource(DynamoDbClient db, @ConfigProperty(name = "app.table") String table) {
        this.db = db;
        this.table = table;
    }

    @GET
    public List<Map<String, Object>> list() {
        List<Map<String, Object>> orders = new ArrayList<>();
        db.scanPaginator(b -> b.tableName(table))
                .items()
                .forEach(item -> orders.add(flatten(item)));
        return orders;
    }

    @GET
    @Path("/{orderId}")
    public Map<String, Object> get(@PathParam("orderId") String orderId) {
        Map<String, AttributeValue> item = db.getItem(b -> b
                .tableName(table)
                .key(Map.of("orderId", AttributeValue.fromS(orderId)))).item();
        if (item == null || item.isEmpty()) {
            throw new NotFoundException("Order " + orderId + " not found");
        }
        return flatten(item);
    }

    /** Collapse a DynamoDB item into plain JSON-friendly values. */
    private static Map<String, Object> flatten(Map<String, AttributeValue> item) {
        Map<String, Object> out = new LinkedHashMap<>();
        item.forEach((k, v) -> out.put(k, render(v)));
        return out;
    }

    private static Object render(AttributeValue v) {
        if (v.s() != null) return v.s();
        if (v.n() != null) return v.n();
        if (v.bool() != null) return v.bool();
        if (v.hasL()) {
            List<Object> list = new ArrayList<>();
            v.l().forEach(e -> list.add(render(e)));
            return list;
        }
        if (v.hasM()) return flatten(v.m());
        return v.toString();
    }
}

package io.floci.workshop.api;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/** A friendly landing page so hitting the base URL in a browser shows something. */
@Path("/")
public class IndexResource {

    @GET
    @Produces(MediaType.TEXT_HTML)
    public String index() {
        String host = System.getenv().getOrDefault("HOSTNAME", "unknown");
        return """
            <!doctype html>
            <title>order-api on Floci ECS</title>
            <h1>order-api</h1>
            <p>A Quarkus web app running as a real ECS container on Floci,
               serving the orders your CLI placed and the Lambda processed.</p>
            <p>Container hostname: <code>%s</code></p>
            <ul>
              <li><a href="/orders">/orders</a> — every order in DynamoDB</li>
              <li><code>/orders/{orderId}</code> — one order</li>
              <li><a href="/q/health">/q/health</a> — readiness</li>
            </ul>
            """.formatted(host);
    }
}

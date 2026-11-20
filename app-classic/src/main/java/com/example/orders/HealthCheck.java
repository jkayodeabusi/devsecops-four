package com.example.orders;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * Container health check. The runtime image is distroless (no shell, no curl),
 * so Docker's HEALTHCHECK runs this class with the JVM that is already there.
 * Exit 0 = healthy, 1 = unhealthy.
 */
public final class HealthCheck {

    private HealthCheck() {
    }

    public static void main(String[] args) {
        String port = System.getenv().getOrDefault("PORT", "8080");
        try {
            var res = HttpClient.newHttpClient().send(
                    HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/health"))
                            .timeout(Duration.ofSeconds(2)).build(),
                    HttpResponse.BodyHandlers.discarding());
            System.exit(res.statusCode() == 200 ? 0 : 1);
        } catch (Exception e) {
            System.exit(1);
        }
    }
}

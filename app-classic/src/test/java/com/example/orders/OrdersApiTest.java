package com.example.orders;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Integration tests: start the real server on a free port and call it over HTTP. */
class OrdersApiTest {

    private static OrderTrackingApp app;
    private static final HttpClient http = HttpClient.newHttpClient();

    @BeforeAll
    static void start() throws Exception {
        app = new OrderTrackingApp(0);   // port 0 = any free port
        app.start();
    }

    @AfterAll
    static void stop() {
        app.stop();
    }

    private static HttpResponse<String> call(String method, String path) throws Exception {
        var req = HttpRequest.newBuilder(URI.create("http://localhost:" + app.port() + path))
                .method(method, HttpRequest.BodyPublishers.noBody()).build();
        return http.send(req, HttpResponse.BodyHandlers.ofString());
    }

    @Test
    void healthIsOk() throws Exception {
        assertEquals(200, call("GET", "/health").statusCode());
    }

    @Test
    void returnsAnOrder() throws Exception {
        var res = call("GET", "/orders/ORD-100002");
        assertEquals(200, res.statusCode());
        assertTrue(res.body().contains("\"status\":\"DELIVERED\""));
    }

    @Test
    void unknownOrderIs404() throws Exception {
        assertEquals(404, call("GET", "/orders/ORD-999999").statusCode());
    }

    @Test
    void badIdIs400AndNotEchoed() throws Exception {
        var res = call("GET", "/orders/%3Cscript%3E");
        assertEquals(400, res.statusCode());
        assertFalse(res.body().contains("script"));
    }

    @Test
    void writesAreRefused() throws Exception {
        assertEquals(405, call("DELETE", "/orders/ORD-100001").statusCode());
    }

    @Test
    void everyResponseHasSecurityHeaders() throws Exception {
        for (String path : new String[] {"/health", "/orders/ORD-100001", "/nope"}) {
            var h = call("GET", path).headers();
            assertEquals("nosniff", h.firstValue("X-Content-Type-Options").orElse(""));
            assertEquals("DENY", h.firstValue("X-Frame-Options").orElse(""));
            assertTrue(h.firstValue("Content-Security-Policy").isPresent());
        }
    }
}

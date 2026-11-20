package com.example.orders;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;

/**
 * Order Tracking API.
 *   GET /health              -> {"status":"ok"}
 *   GET /orders/ORD-100001   -> the order as JSON
 * Uses the JDK's built-in HTTP server, so the image ships no third-party code.
 */
public final class OrderTrackingApp {

    private final HttpServer server;
    private final OrderStore store = new OrderStore();

    public OrderTrackingApp(int port) throws IOException {
        server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/health", ex -> send(ex, 200, "{\"status\":\"ok\"}"));
        server.createContext("/orders/", this::orders);
        server.createContext("/", ex -> send(ex, 404, "{\"error\":\"not found\"}"));
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
    }

    private void orders(HttpExchange ex) throws IOException {
        if (!"GET".equals(ex.getRequestMethod())) {
            ex.getResponseHeaders().set("Allow", "GET");
            send(ex, 405, "{\"error\":\"method not allowed\"}");
            return;
        }
        String id = ex.getRequestURI().getPath().substring("/orders/".length());
        if (!OrderStore.isValidId(id)) {
            // Never echo the bad input back: that is how reflected XSS starts.
            send(ex, 400, "{\"error\":\"invalid order id\"}");
            return;
        }
        var order = store.find(id);
        if (order.isPresent()) {
            send(ex, 200, order.get().toJson());
        } else {
            send(ex, 404, "{\"error\":\"order not found\"}");
        }
    }

    /** Every response carries the same security headers (what the ZAP baseline checks for). */
    static void send(HttpExchange ex, int status, String json) throws IOException {
        byte[] body = json.getBytes(StandardCharsets.UTF_8);
        var h = ex.getResponseHeaders();
        h.set("Content-Type", "application/json; charset=utf-8");
        h.set("X-Content-Type-Options", "nosniff");
        h.set("X-Frame-Options", "DENY");
        h.set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
        h.set("Referrer-Policy", "no-referrer");
        h.set("Cache-Control", "no-store");
        h.set("Cross-Origin-Resource-Policy", "same-origin");
        h.set("Permissions-Policy", "geolocation=(), camera=(), microphone=()");
        ex.sendResponseHeaders(status, body.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(body);
        }
    }

    public void start() {
        server.start();
    }

    public void stop() {
        server.stop(0);
    }

    public int port() {
        return server.getAddress().getPort();
    }

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        var app = new OrderTrackingApp(port);
        Runtime.getRuntime().addShutdownHook(new Thread(app::stop));   // clean stop on SIGTERM
        app.start();
        System.out.println("order-tracking listening on :" + app.port());
    }
}

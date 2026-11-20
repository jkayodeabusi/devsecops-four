package com.example.orders;

import java.util.Map;
import java.util.Optional;
import java.util.regex.Pattern;

/** In-memory order data. A real service would call a database; the demo needs none. */
public final class OrderStore {

    /** Allow-list validation: an order ID is "ORD-" plus exactly six digits, nothing else. */
    static final Pattern ORDER_ID = Pattern.compile("^ORD-[0-9]{6}$");

    private final Map<String, Order> orders = Map.of(
            "ORD-100001", new Order("ORD-100001", "IN_TRANSIT", "Canada Post", "2026-11-21"),
            "ORD-100002", new Order("ORD-100002", "DELIVERED", "Purolator", "2026-11-18"),
            "ORD-100003", new Order("ORD-100003", "PROCESSING", "UPS", "2026-11-24"));

    public static boolean isValidId(String id) {
        return id != null && ORDER_ID.matcher(id).matches();
    }

    public Optional<Order> find(String id) {
        if (!isValidId(id)) {
            return Optional.empty();
        }
        return Optional.ofNullable(orders.get(id));
    }
}

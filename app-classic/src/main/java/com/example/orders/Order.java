package com.example.orders;

/** One tracked order. A record is immutable, so a handler can never change stored data. */
public record Order(String id, String status, String carrier, String eta) {

    /** Hand-built JSON: four known fields, every value escaped. */
    public String toJson() {
        return "{\"id\":\"" + Json.escape(id)
                + "\",\"status\":\"" + Json.escape(status)
                + "\",\"carrier\":\"" + Json.escape(carrier)
                + "\",\"eta\":\"" + Json.escape(eta) + "\"}";
    }
}

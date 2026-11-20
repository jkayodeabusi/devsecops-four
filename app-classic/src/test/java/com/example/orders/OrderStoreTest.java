package com.example.orders;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OrderStoreTest {

    private final OrderStore store = new OrderStore();

    @Test
    void findsAKnownOrder() {
        assertEquals("IN_TRANSIT", store.find("ORD-100001").orElseThrow().status());
    }

    @Test
    void unknownButValidIdIsEmpty() {
        assertTrue(store.find("ORD-999999").isEmpty());
    }

    // Security tests: the validator is the app's main input defence, so it gets its own cases.
    @ParameterizedTest
    @ValueSource(strings = {"", "ORD-1", "ORD-1000011", "ord-100001", "ORD-10000A",
            "../etc/passwd", "ORD-100001' OR '1'='1", "<script>", "ORD-100001\n"})
    void rejectsAnythingOutsideTheAllowList(String id) {
        assertFalse(OrderStore.isValidId(id));
    }

    @Test
    void jsonEscapingKeepsValuesInsideTheirQuotes() {
        String json = new Order("x\"}", "<b>", "a\\b", "line\nbreak").toJson();
        assertTrue(json.contains("x\\\"}"));
        assertTrue(json.contains("\\u003cb\\u003e"));
        assertTrue(json.contains("line\\nbreak"));
    }
}

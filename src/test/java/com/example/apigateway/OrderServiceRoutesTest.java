package com.example.apigateway;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.junit.jupiter.api.Assertions.assertEquals;

/**
 * Every OrderService controller prefix must be reachable through the gateway, and the customer / admin session
 * headers must reach OrderService unchanged. A fake OrderService echoes which path it was asked for, so a prefix
 * with no route fails with a 404 instead of the echo.
 */
@SpringBootTest
@AutoConfigureMockMvc
class OrderServiceRoutesTest {
    private static final AtomicReference<String> LAST_CUSTOMER_TOKEN = new AtomicReference<>();
    private static final AtomicReference<String> LAST_ADMIN_TOKEN = new AtomicReference<>();
    private static final HttpServer FAKE_ORDER_SERVICE = startFakeOrderService();

    @Autowired
    private MockMvc mockMvc;

    private static HttpServer startFakeOrderService() {
        try {
            HttpServer server = HttpServer.create(new InetSocketAddress("localhost", 0), 0);
            server.createContext("/", exchange -> {
                LAST_CUSTOMER_TOKEN.set(exchange.getRequestHeaders().getFirst("X-Customer-Token"));
                LAST_ADMIN_TOKEN.set(exchange.getRequestHeaders().getFirst("X-Admin-Token"));
                byte[] body = ("order-service:" + exchange.getRequestURI().getPath()).getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("Content-Type", "text/plain");
                exchange.sendResponseHeaders(200, body.length);
                try (OutputStream os = exchange.getResponseBody()) {
                    os.write(body);
                }
            });
            server.start();
            return server;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    @AfterAll
    static void stopFakeOrderService() {
        FAKE_ORDER_SERVICE.stop(0);
    }

    @DynamicPropertySource
    static void overrideOrderServiceUrl(DynamicPropertyRegistry registry) {
        registry.add("order.service.url", () -> "http://localhost:" + FAKE_ORDER_SERVICE.getAddress().getPort());
    }

    @ParameterizedTest
    @ValueSource(strings = {"cart", "coupons", "wishlist", "addresses", "admin", "audit", "customer", "faq", "feedback",
            "giftcards", "gst", "loyalty", "ordernotes", "pincodes", "prefs", "questions", "referral", "savedcart",
            "storecredit", "subscriptions", "support", "waitlist"})
    void everyOrderServicePrefixIsRouted(String prefix) throws Exception {
        mockMvc.perform(get("/" + prefix + "/anything"))
                .andExpect(status().isOk())
                .andExpect(content().string("order-service:/" + prefix + "/anything"));
    }

    @Test
    void forwardsTheCustomerAndAdminSessionHeadersUnchanged() throws Exception {
        mockMvc.perform(get("/customer/session").header("X-Customer-Token", "cust-token")
                        .header("X-Admin-Token", "admin-token"))
                .andExpect(status().isOk());
        assertEquals("cust-token", LAST_CUSTOMER_TOKEN.get());
        assertEquals("admin-token", LAST_ADMIN_TOKEN.get());
    }
}

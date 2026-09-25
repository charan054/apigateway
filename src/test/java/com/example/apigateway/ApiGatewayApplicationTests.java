package com.example.apigateway;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;
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

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Verifies the gateway actually forwards requests to the right downstream service and returns its response
 * verbatim - not just that the routes parse. Stands in a plain JDK HttpServer as a fake "ProductService" (no
 * extra test dependency needed) and points the product route at it for the duration of this test only.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ApiGatewayApplicationTests {

    private static final AtomicReference<String> LAST_RECEIVED_SERVICE_KEY = new AtomicReference<>();
    private static final HttpServer FAKE_PRODUCT_SERVICE = startFakeProductService();

    @Autowired
    private MockMvc mockMvc;

    private static HttpServer startFakeProductService() {
        try {
            HttpServer server = HttpServer.create(new InetSocketAddress("localhost", 0), 0);
            server.createContext("/product/all", exchange -> {
                LAST_RECEIVED_SERVICE_KEY.set(exchange.getRequestHeaders().getFirst("X-Service-Key"));
                byte[] body = "[{\"productName\":\"Widget\"}]".getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("Content-Type", "application/json");
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
    static void stopFakeProductService() {
        FAKE_PRODUCT_SERVICE.stop(0);
    }

    @DynamicPropertySource
    static void overrideProductServiceUrl(DynamicPropertyRegistry registry) {
        registry.add("product.service.url", () -> "http://localhost:" + FAKE_PRODUCT_SERVICE.getAddress().getPort());
    }

    @Test
    void routesProductRequestsToProductServiceAndReturnsItsResponseVerbatim() throws Exception {
        mockMvc.perform(get("/product/all"))
                .andExpect(status().isOk())
                .andExpect(content().string("[{\"productName\":\"Widget\"}]"));
    }

    @Test
    void forwardsTheXServiceKeyHeaderUnchanged() throws Exception {
        mockMvc.perform(get("/product/all").header("X-Service-Key", "some-service-key"))
                .andExpect(status().isOk());
        assertEquals("some-service-key", LAST_RECEIVED_SERVICE_KEY.get());
    }

    @Test
    void aPathThatMatchesNoRouteReturns404() throws Exception {
        mockMvc.perform(get("/unknown/path")).andExpect(status().isNotFound());
    }
}

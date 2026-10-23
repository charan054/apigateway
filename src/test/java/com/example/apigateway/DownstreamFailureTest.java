package com.example.apigateway;

import jakarta.servlet.ServletException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.client.ResourceAccessException;

import java.io.IOException;
import java.net.ConnectException;
import java.net.ServerSocket;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.net.http.HttpTimeoutException;
import java.nio.channels.ClosedChannelException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A backend that is not running must give the caller a 502 (or 504 for a timeout) with a short JSON body, not an
 * opaque 500 - checked end to end against a port nothing listens on, and for each kind of failure in isolation.
 */
@SpringBootTest
@AutoConfigureMockMvc
class DownstreamFailureTest {
    private static final int CLOSED_PORT = closedPort();

    @Autowired
    private MockMvc mockMvc;

    private static int closedPort() {
        try (ServerSocket socket = new ServerSocket(0)) {
            return socket.getLocalPort();
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    @DynamicPropertySource
    static void pointProductRouteAtNothing(DynamicPropertyRegistry registry) {
        registry.add("product.service.url", () -> "http://localhost:" + CLOSED_PORT);
    }

    @Test
    void aStoppedServiceIsA502WithAShortJsonBody() throws Exception {
        mockMvc.perform(get("/product/all"))
                .andExpect(status().isBadGateway())
                .andExpect(content().contentTypeCompatibleWith("application/json"))
                .andExpect(jsonPath("$.status").value(502))
                .andExpect(jsonPath("$.error").value("The service behind this request is not reachable right now"));
    }

    @Test
    void classifiesEachKindOfFailedProxyCall() {
        assertEquals(502, DownstreamFailureFilter.classify(wrap(new ConnectException("Connection refused"))));
        assertEquals(502, DownstreamFailureFilter.classify(wrap(new ClosedChannelException())));
        assertEquals(502, DownstreamFailureFilter.classify(wrap(new UnknownHostException("nope"))));
        assertEquals(504, DownstreamFailureFilter.classify(wrap(new HttpTimeoutException("request timed out"))));
        assertEquals(504, DownstreamFailureFilter.classify(wrap(new SocketTimeoutException("Read timed out"))));
    }

    @Test
    void leavesEverythingThatIsNotAFailedProxyCallAlone() {
        assertEquals(0, DownstreamFailureFilter.classify(new IllegalStateException("bug")));
        assertEquals(0, DownstreamFailureFilter.classify(new ServletException(new IOException("Broken pipe"))));
        assertEquals(0, DownstreamFailureFilter.classify(new ServletException(new SocketTimeoutException("client was slow"))));
    }

    @Test
    void theFilterRethrowsWhatItDoesNotRecognise() {
        DownstreamFailureFilter filter = new DownstreamFailureFilter();
        IllegalStateException bug = new IllegalStateException("bug");
        MockHttpServletResponse response = new MockHttpServletResponse();

        IllegalStateException thrown = assertThrows(IllegalStateException.class, () -> filter.doFilter(
                new MockHttpServletRequest("GET", "/x"), response,
                (req, res) -> { throw bug; }));

        assertSame(bug, thrown);
        assertEquals(200, response.getStatus());
    }

    @Test
    void theFilterAnswers504ForATimeoutAndPassesNormalResponsesThrough() throws Exception {
        DownstreamFailureFilter filter = new DownstreamFailureFilter();
        MockHttpServletResponse timedOut = new MockHttpServletResponse();
        filter.doFilter(new MockHttpServletRequest("GET", "/x"), timedOut,
                (req, res) -> { throw new ServletException(wrap(new HttpTimeoutException("slow"))); });
        assertEquals(504, timedOut.getStatus());
        assertTrue(timedOut.getContentAsString().contains("took too long"));

        MockHttpServletResponse fine = new MockHttpServletResponse();
        filter.doFilter(new MockHttpServletRequest("GET", "/x"), fine, new MockFilterChain());
        assertEquals(200, fine.getStatus());
    }

    private static ResourceAccessException wrap(IOException cause) {
        return new ResourceAccessException("I/O error on GET request", cause);
    }
}

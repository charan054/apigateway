package com.example.apigateway;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.net.SocketTimeoutException;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;

/**
 * Turns "the service behind this route could not be reached" into the answer a gateway should give. When the downstream
 * connection fails (service stopped or restarting, connection refused, closed, timed out), the proxy call throws and,
 * left alone, the client gets an opaque HTTP 500 and the log gets a full stack trace per request. This answers 502 Bad
 * Gateway instead - or 504 Gateway Timeout when it was a timeout - with a short JSON body, and logs one line.
 * <p>
 * Only failures of the proxy call itself (a {@link ResourceAccessException} in the cause chain) are translated. A
 * downstream service that answers, even with a 4xx or 5xx, is passed through untouched, and unrelated errors (including
 * a client that hung up mid-response) are rethrown as before.
 */
@Component
public class DownstreamFailureFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(DownstreamFailureFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        try {
            chain.doFilter(request, response);
        } catch (ServletException | RuntimeException e) {
            int status = classify(e);
            if (status == 0 || response.isCommitted()) {
                throw e;
            }
            log.warn("{} {} -> {}: {}", request.getMethod(), request.getRequestURI(), status, rootMessage(e));
            response.resetBuffer();
            response.setStatus(status);
            response.setContentType("application/json");
            response.setCharacterEncoding(StandardCharsets.UTF_8.name());
            String message = status == HttpServletResponse.SC_GATEWAY_TIMEOUT
                    ? "The service behind this request took too long to answer"
                    : "The service behind this request is not reachable right now";
            response.getWriter().write("{\"status\":" + status + ",\"error\":\"" + message + "\"}");
        }
    }

    /** 504 for a timeout, 502 for any other failed proxy call, 0 when this is not a failed proxy call at all. */
    static int classify(Throwable error) {
        boolean proxyCallFailed = false;
        boolean timeout = false;
        for (Throwable t = error; t != null; t = t.getCause() == t ? null : t.getCause()) {
            if (t instanceof ResourceAccessException) {
                proxyCallFailed = true;
            }
            if (t instanceof HttpTimeoutException || t instanceof SocketTimeoutException) {
                timeout = true;
            }
        }
        if (!proxyCallFailed) {
            return 0;
        }
        return timeout ? HttpServletResponse.SC_GATEWAY_TIMEOUT : HttpServletResponse.SC_BAD_GATEWAY;
    }

    private static String rootMessage(Throwable error) {
        Throwable root = error;
        while (root.getCause() != null && root.getCause() != root) {
            root = root.getCause();
        }
        return root.getClass().getSimpleName() + (root.getMessage() == null ? "" : " - " + root.getMessage());
    }
}

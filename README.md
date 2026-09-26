# ApiGateway

A Spring Cloud Gateway (WebMVC) instance that routes requests by path prefix to the four backend services in this project. It does no auth, transformation, or rate limiting of its own — each downstream service still enforces its own security (`X-Service-Key`, buyer session tokens, etc.) exactly as if it were called directly.

## Routes

| Path prefix | Routed to | Backing service |
|---|---|---|
| `/bank/**` | `bank.service.url` | Bankapplication |
| `/phonepe/**` | `phonepe.service.url` | PhonepayService |
| `/product/**` | `product.service.url` | ProductService |
| `/cart/**` | `order.service.url` | OrderService |

Defined in [`src/main/resources/application.yml`](src/main/resources/application.yml).

**Known gap:** OrderService's `/coupons/**` and `/wishlist/**` endpoints and ProductService's `/category/**` endpoints have no route here yet — they were added directly to those services without updating this gateway. Call them on the service's own port (8083 / 8082) directly, or add matching route entries here, following the same pattern as the existing four.

## Running it

```bash
./mvnw spring-boot:run
```

Starts on port `9000` (see `application.yml`). It expects the four backend services to already be reachable at their default ports (Bankapplication `8080`, PhonepayService `8081`, ProductService `8082`, OrderService `8083`) or wherever the env vars below point.

## Configuration

Each downstream address can be overridden with an environment variable instead of editing `application.yml`, matching the convention OrderService's own Feign clients already use:

| Env var | Default |
|---|---|
| `BANK_SERVICE_URL` | `http://localhost:8080` |
| `PHONEPE_SERVICE_URL` | `http://localhost:8081` |
| `PRODUCT_SERVICE_URL` | `http://localhost:8082` |
| `ORDER_SERVICE_URL` | `http://localhost:8083` |

## Actuator

`application.yml` lists `health,info,gateway` under `management.endpoints.web.exposure.include`, but only `/actuator/health` and `/actuator/info` are actually live on the WebMVC-flavored gateway (`spring-cloud-starter-gateway-server-webmvc`) as currently wired up - `/actuator/gateway` 404s. Getting the routes endpoint working would need investigating why it isn't auto-registering (possibly a missing dependency or property for this WebMVC variant, as opposed to the reactive `spring-cloud-starter-gateway`).

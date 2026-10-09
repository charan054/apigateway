# ApiGateway

A Spring Cloud Gateway (WebMVC) instance that routes requests by path prefix to the four backend services in this project. It does no auth, transformation, or rate limiting of its own — each downstream service still enforces its own security (`X-Service-Key`, buyer session tokens, etc.) exactly as if it were called directly.

## Routes

| Path prefix | Routed to | Backing service |
|---|---|---|
| `/bank/**` | `bank.service.url` | Bankapplication |
| `/phonepe/**` | `phonepe.service.url` | PhonepayService |
| `/product/**` | `product.service.url` | ProductService |
| `/category/**` | `product.service.url` | ProductService |
| `/cart/**` | `order.service.url` | OrderService |
| `/coupons/**` | `order.service.url` | OrderService |
| `/wishlist/**` | `order.service.url` | OrderService |
| `/addresses/**`, `/admin/**`, `/audit/**`, `/customer/**`, `/faq/**`, `/feedback/**`, `/giftcards/**`, `/gst/**`, `/loyalty/**`, `/ordernotes/**`, `/pincodes/**`, `/prefs/**`, `/questions/**`, `/referral/**`, `/savedcart/**`, `/storecredit/**`, `/subscriptions/**`, `/support/**`, `/waitlist/**` | `order.service.url` | OrderService |
| `/uploads/**` | `product.service.url` | ProductService (uploaded product images) |

Defined in [`src/main/resources/application.yml`](src/main/resources/application.yml).

## Running it

```bash
./mvnw spring-boot:run
```

Starts on port `9000` (see `application.yml`). It expects the four backend services to already be reachable at their default ports (Bankapplication `8080`, PhonepayService `8081`, ProductService `8082`, OrderService `8083`) or wherever the env vars below point.

### Running the whole stack

`dev-scripts/` starts and stops all five services together (Windows PowerShell; the five repos must be sibling folders, e.g. `D:\charan\Bankapplication`, `D:\charan\OrderService`, ...). MySQL must already be running; Kafka is optional.

```powershell
powershell -ExecutionPolicy Bypass -File dev-scripts\start-all.ps1                         # start everything, in dependency order
powershell -ExecutionPolicy Bypass -File dev-scripts\start-all.ps1 -Only OrderService -Restart   # replace one stale server
powershell -ExecutionPolicy Bypass -File dev-scripts\status.ps1                            # what's running (plus MySQL/Kafka)
powershell -ExecutionPolicy Bypass -File dev-scripts\stop-all.ps1                          # stop everything
powershell -ExecutionPolicy Bypass -File dev-scripts\smoke.ps1                            # is the whole stack actually working? (exit 1 on any failure)
```

Each service runs `mvnw spring-boot:run` hidden in the background with Java 23 (`-JavaHome` to override), logging to `dev.log` / `dev.err.log` in its own repo folder. A service already listening on its port is left alone unless `-Restart` is passed.

`smoke.ps1` checks that all five services listen, the catalog answers directly and through this gateway, the storefront and FAQ are served, an anonymous caller is refused on a protected endpoint, and - when the service key is available (`-ServiceKey`, `INTERNAL_SERVICE_API_KEY`, or OrderService\.env) - that the health board is green and a cash-on-delivery order can be placed and cancelled with the stock restored. The order check leaves one cancelled order for the throwaway phone number `9000000999` in the dev database; pass `-SkipOrder` to avoid that. The key is only sent as a request header, never printed.

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

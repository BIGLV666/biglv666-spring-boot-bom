# web-common-spring-boot-starter

Lightweight Spring Boot starter for the web layer: a unified `Result` response body + segmented error-code enums + global exception handling + automatic response wrapping. Works out of the box — zero code, zero configuration.

[简体中文](README.md)

## Quick Start

```xml
<dependency>
    <groupId>io.github.biglv666</groupId>
    <artifactId>web-common-spring-boot-starter</artifactId>
    <version>0.3.0</version>
</dependency>
```

Requires Spring Boot 3.x or 4.x (Servlet web application) and Java 17+. Automatic wrapping of String return values adapts to Jackson 2 (default on Boot 3.x) and Jackson 3 (default on Boot 4) based on the classpath — no extra JSON dependency needed.

## Unified Response Structure

HTTP status is always 200; success or failure is indicated by `code`:

```json
{ "code": 0, "message": "操作成功", "data": { } }
```

## Automatic Response Wrapping (enabled by default)

Controllers return business objects directly; the starter wraps them into `Result` automatically, no `Result.ok(...)` boilerplate:

```java
@GetMapping("/user/{id}")
public UserVO getUser(@PathVariable Long id) {   // response becomes {"code":0,...,"data":{...}}
    return userService.getById(id);
}
```

When raw output is needed (file downloads, health checks, etc.), annotate the method or class with `@NoWrap` to opt out. Explicitly returning `Result` also works; both styles mix freely.

## Business Exceptions

Throw a `BusinessException` in business logic; the global exception handler turns it into a unified failure response:

```java
// Built-in error code + default message
throw new BusinessException(ResultCode.NOT_FOUND);

// Built-in error code + custom message
throw new BusinessException(ResultCode.CONFLICT, "username already taken");

// Message template: {} placeholders filled in order
throw BusinessException.of(OrderErrorCode.STOCK_NOT_ENOUGH, "insufficient stock, {} left", 3);
```

## Declarative Error Mapping: adopt existing domain exceptions without refactoring

Already have domain exceptions extending `RuntimeException`? Annotate them with `@DefaultErrorCode` — no inheritance changes needed:

```java
// For single-constant enums, the class alone is enough; multi-constant enums (like ResultCode) require `constant`
@DefaultErrorCode(value = OrderErrorCode.class, constant = "ORDER_NOT_FOUND")
public class OrderNotFoundException extends RuntimeException {
    public OrderNotFoundException(String message) { super(message); }
}
```

The response `code` comes from the annotation, and `message` from the exception itself (falling back to the error code's default message when empty).

## Custom Error Codes

Implement the `ErrorCode` interface with a new enum and declare it under `web-common.error-codes` to join the startup-time validation:

```java
public enum OrderErrorCode implements ErrorCode {
    STOCK_NOT_ENOUGH(51001, "insufficient stock"),
    ORDER_ALREADY_PAID(51002, "order already paid");

    // implement getCode() / getMessage()
}
```

To skip listing class names one by one, annotate any `@Configuration` class with `@ErrorCodeScan` to register `ErrorCode` enums by package scan (defaults to the annotated class's package). Both approaches can be combined:

```java
@Configuration
@ErrorCodeScan("com.example.order")
public class WebConfig { }
```

At startup the starter validates **duplicate codes, out-of-segment codes (only 0, 500, and 40000~59999 are allowed), and reserved values (0/500)**; any conflict fails startup immediately — error-code conflicts discovered at runtime are a debugging disaster. Segment conventions: `0` success; `4xxxx` client-side; `5xxxx` business-side; `500` system fallback. See the Javadoc on each `ResultCode` constant for when to use the built-in codes.

## Error-Code Dictionary Endpoint

Error codes live across business enums; syncing them to frontend and QA by hand invites mistakes. Annotate any `@Configuration` class with `@EnableErrorCodeEndpoint` to expose `GET /web-common/error-codes`:

```java
@Configuration
@EnableErrorCodeEndpoint
public class WebConfig { }
```

The endpoint returns every error code that passed startup validation (built-in + business-declared, with default messages and source enums, sorted by code) for frontend, QA, and gateway consumption. Off by default; annotate to enable — no configuration needed:

```json
{
  "code": 0, "message": "操作成功",
  "data": [
    { "code": 40000, "message": "参数错误", "enumClass": "...ResultCode", "constant": "PARAM_ERROR" },
    { "code": 51001, "message": "库存不足", "enumClass": "com.example.order.OrderErrorCode", "constant": "STOCK_NOT_ENOUGH" }
  ]
}
```

If the fixed path conflicts with business routes, or a custom output shape is needed, declare your own controller, inject `ErrorCodeRegistry`, and call `descriptors()` to read the same dictionary.

## Global Exception Handling Coverage

| Exception | Response |
|---|---|
| `BusinessException` | code and message carried by the exception |
| Custom exceptions annotated with `@DefaultErrorCode` | code declared by the annotation and the exception's message |
| `@Valid` request-body / form validation failure | `40000` + 「field: reason」detail, with a structured detail list in `data` |
| `@Validated` single-parameter validation failure | `40000` + 「parameter: reason」detail, with a structured detail list in `data` |
| Constraint annotations directly on method parameters (Spring 6.1+ built-in validation) | `40000` + 「parameter: reason」detail, with a structured detail list in `data` |
| JSON deserialization failure | `40000` malformed request body (type mismatches append the offending field path, e.g. `field orders[0].count type mismatch`) |
| Upload file exceeding size limit | `40000` uploaded file too large |
| Unsupported method / missing parameter / type conversion failure, etc. | `40000` |
| Path not found (incl. Spring 6.1+ static resource misses) | `40400` |
| Any other unrecognized exception | `500` system busy; stack trace goes to logs only |

Structured validation details look like `"data": [{ "field": "age", "message": "年龄必须为正数" }]` so frontends can highlight form fields directly; the joined text in `message` is unchanged for logs and human readers. In other failure scenarios `data` is omitted. Deserialization field paths only expose JSON field names — no target types or internal class names.

## HTTP Status Code Modes

By default HTTP status is always 200 and success is judged by `code`. To let gateways and monitoring recognize semantic status codes, enable `semantic` mode: `0`→200; `40400`→404; `500`→500; other `4xxxx`→400; `5xxxx` business codes→200 (business failures are not server-side faults; returning 5xx would falsely trigger gateway alerts and retries). The response body shape is unchanged, but consumers must adjust gateway and monitoring policies accordingly:

```yaml
web-common:
  http-status-mode: SEMANTIC   # default ALWAYS_200, consistent with the 0.2.0 contract
```

## Configuration

```yaml
web-common:
  enabled: true                     # default true; set false to disable the whole starter
  auto-wrap: true                   # default true; toggles automatic response wrapping
  success-message: 操作成功          # success message, fully replaceable (e.g. "OK")
  http-status-mode: ALWAYS_200      # default always 200; SEMANTIC maps semantic status codes by code segment
  expose-exception-message: false   # default false; enable temporarily while debugging, MUST be off in production
  error-codes:                      # business error-code enums, validated at startup (or use @ErrorCodeScan)
    - com.example.order.OrderErrorCode
  log:
    business-level: WARN            # log level for business exceptions, default WARN
    param-level: WARN               # log level for parameter-type exceptions, default WARN
    system-level: ERROR             # log level for system fallback exceptions, default ERROR
```

Every exception branch logs the request URI, and levels are adjustable. Consumers may declare their own `GlobalExceptionHandler` / `ResultWrapAdvice` beans to override the defaults.

## API Documentation (springdoc / knife4j)

Once the consumer project has springdoc-openapi or knife4j, the descriptions and example values on `Result` fields (from class-level Swagger annotations) appear in the generated docs automatically — no need to redefine the response structure.

## Example Project

[`examples/demo-app`](examples/demo-app) is a runnable, complete example (custom error codes, declarative exceptions, `@NoWrap`, etc.). First run `./mvnw install` at the repository root to install the starter locally, then run `../../mvnw -f pom.xml spring-boot:run` from the example directory.

## Release

Maintainers push a `v*` tag to publish to Maven Central automatically (GitHub Actions, see `.github/workflows/publish.yml`); pushes to `main` and pull requests run the full test suite via `.github/workflows/build.yml`:

```bash
git tag v0.3.0 && git push origin v0.3.0
```

## Local Build

```bash
mvnw test        # run the integration test suite (49 test cases)
mvnw package     # package (jar + sources + javadoc)
```

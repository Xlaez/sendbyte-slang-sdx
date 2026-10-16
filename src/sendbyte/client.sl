// SendByte client core: configuration, transport, retries, errors.
//
// Every API call in this package flows through `do_json` / `do_bytes`
// below, so auth headers, error decoding, retry policy, and request-id
// capture live in exactly one place. Mirrors the Go SDK's request loop
// (bearer auth, JSON bodies, retries on 429/5xx honoring Retry-After,
// typed errors with a non-JSON fallback).

import "httpc";
import "strings";
import "json";
import "time";

// A SendByte API client. Share one per process: it holds a pooled
// httpc.Client, so concurrent `spawn`ed tasks reuse connections.
pub gc struct Client {
    key: str,
    base: str,
    http: httpc.Client,
    // Default per-request budget in nanoseconds, used by helpers that
    // take no explicit deadline. 30 seconds.
    timeout_ns: int,
    // Total attempts per request including the first try. Retries apply
    // to 429 and 5xx only; anything else fails immediately.
    max_attempts: int
}

// Structured API failure, mirroring the Go SDK's Error and the API's
// `{ "error": { "code", "message", "docs_url" } }` envelope. Branch on
// `code` (e.g. "rate_limit_exceeded"), never on `message`.
pub gc struct ApiError {
    code: str,
    message: str,
    docs_url: str,
    status: int,
    request_id: str
}

// The `{ "error": {...} }` envelope, for decoding failure bodies.
gc struct ErrorEnvelope {
    error: ErrorBody
}

gc struct ErrorBody {
    code: str,
    message: str,
    docs_url: str
}

// A decoded successful response before it is handed to a resource
// decoder: status, body text, and the request id for log correlation.
gc struct RawResponse {
    status: int,
    body: str,
    request_id: str
}

// Build a client for any key. Prefer new_test_client / new_live_client:
// they reject the wrong key family at startup instead of at 2am.
pub fn new_client(key: str) -> result[Client, str] {
    if key == "" {
        return err("sendbyte: empty API key; pass sk_test_... or sk_live_...");
    }
    let c = Client {
        key: key,
        base: "https://api.sendbyte.africa",
        http: httpc.new_client(),
        timeout_ns: 30000000000,
        max_attempts: 3
    };
    return ok(c);
}

// Build a client that only accepts sandbox keys. Sandbox traffic is
// simulated end to end and never delivers.
pub fn new_test_client(key: str) -> result[Client, str] {
    if !strings.has_prefix(key, "sk_test_") {
        return err("sendbyte: not a sandbox key (want sk_test_...)");
    }
    return new_client(key);
}

// Build a client that only accepts live keys. Live traffic delivers
// to real inboxes and bills the account.
pub fn new_live_client(key: str) -> result[Client, str] {
    if !strings.has_prefix(key, "sk_live_") {
        return err("sendbyte: not a live key (want sk_live_...)");
    }
    return new_client(key);
}

// Point the client at a different host (staging, mocks, replay tests).
// Mutates the shared client, so call it once at startup.
pub fn with_base_url(c: Client, base: str) -> Client {
    c.base = base;
    return c;
}

// True for live keys, false for test keys and anything else.
pub fn is_live_key(key: str) -> bool {
    return strings.has_prefix(key, "sk_live_");
}

// True for sandbox keys, false for anything else.
pub fn is_test_key(key: str) -> bool {
    return strings.has_prefix(key, "sk_test_");
}

// An `until` deadline `seconds` in the future, for call sites that do
// not manage their own budgets.
pub fn deadline_in(seconds: int) -> until {
    return until_of(time.mono() + seconds * 1000000000);
}

// Is this failure a rate limit? Sleep past Retry-After (when the server
// sent one) and retry the same request.
pub fn is_rate_limited(e: ApiError) -> bool {
    return e.code == "rate_limit_exceeded" || e.status == 429;
}

// Render an ApiError the way logs want it: code, status, request id,
// then the human message.
pub fn error_string(e: ApiError) -> str {
    return "sendbyte." + e.code + " (status " + to_str(e.status)
        + ", request " + e.request_id + "): " + e.message;
}

// GET/POST/PUT/PATCH/DELETE with a JSON (or empty) body; decodes the
// error envelope on failure. Retries 429/5xx with backoff.
pub fn do_json(c: Client, method: str, path_query: str, body: opt[str],
               deadline: until) -> result[RawResponse, ApiError] {
    let r = httpc.new_request(method, c.base + path_query);
    r.headers["Authorization"] = "Bearer " + c.key;
    r.headers["Accept"] = "application/json";
    r.headers["User-Agent"] = "sendbyte-slang/0.1.0";
    if let b = body {
        r.headers["Content-Type"] = "application/json";
        r.body = to_bytes(b);
    }
    return do_send(c, r, deadline);
}

// Same as do_json but returns raw bytes: CSV exports, raw message
// content, attachment downloads. Error bodies still decode to ApiError.
pub fn do_bytes(c: Client, method: str, path_query: str, deadline: until)
        -> result[bytes, ApiError] {
    let r = httpc.new_request(method, c.base + path_query);
    r.headers["Authorization"] = "Bearer " + c.key;
    r.headers["Accept"] = "*/*";
    r.headers["User-Agent"] = "sendbyte-slang/0.1.0";
    let rr = do_send_raw(c, r, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(raw.body);
}

// Send one request with retries. Public so resource files share it;
// prefer do_json / do_bytes.
pub fn do_send(c: Client, req: httpc.Request, deadline: until)
        -> result[RawResponse, ApiError] {
    let rr = do_send_raw(c, req, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(RawResponse { status: raw.status, body: to_str(raw.body),
                            request_id: raw.request_id });
}

gc struct RawBytes {
    status: int,
    body: bytes,
    request_id: str
}

// The retry loop. Returns the final response (success or failure body)
// with its request id, or a transport-level ApiError when no HTTP
// exchange happened at all.
fn do_send_raw(c: Client, req: httpc.Request, deadline: until)
        -> result[RawBytes, ApiError] {
    let attempt = 0;
    while true {
        attempt = attempt + 1;
        let rr: result[httpc.Response, str] = httpc.client_send(c.http, req, deadline);
        guard let resp = rr else let e = err_of(rr) {
            // Transport failure (timeout, refused, reset): retryable
            // while attempts remain, fatal afterwards.
            if attempt < c.max_attempts {
                time.sleep(backoff_ns(attempt, ""));
                continue;
            }
            return err(ApiError { code: "request_failed", message: e,
                                  docs_url: "", status: 0, request_id: "" });
        }
        let request_id = response_header(resp, "x-request-id");
        if resp.status == 429 || (resp.status >= 500 && resp.status < 600) {
            if attempt < c.max_attempts {
                time.sleep(backoff_ns(attempt,
                    response_header(resp, "retry-after")));
                continue;
            }
        }
        if resp.status >= 200 && resp.status < 300 {
            return ok(RawBytes { status: resp.status, body: resp.body,
                                 request_id: request_id });
        }
        return err(decode_error(resp, request_id));
    }
    panic("sendbyte: unreachable retry loop");
}

// Decode a failure body into ApiError. Never fails on non-JSON bodies
// (a gateway 502 may be HTML): those become "request_failed", exactly
// like the Go SDK's parseError fallback.
pub fn decode_error_body(status: int, body: str, request_id: str) -> ApiError {
    let r: result[ErrorEnvelope, str] = json.decode(body);
    if let env = r {
        return ApiError { code: env.error.code, message: env.error.message,
                          docs_url: env.error.docs_url, status: status,
                          request_id: request_id };
    }
    return ApiError { code: "request_failed",
                      message: "request failed with status " + to_str(status),
                      docs_url: "", status: status, request_id: request_id };
}

fn decode_error(resp: httpc.Response, request_id: str) -> ApiError {
    return decode_error_body(resp.status, to_str(resp.body), request_id);
}

// Header lookup that tolerates absence (a missing map key panics, and
// Retry-After / x-request-id are optional).
fn response_header(resp: httpc.Response, name: str) -> str {
    if has(resp.headers, name) {
        return resp.headers[name];
    }
    return "";
}

// Exponential backoff with full jitter skipped deliberately: slang has
// no cheap thread-safe jitter source worth plumbing for this, and
// correlated retries across a fleet are the server's Retry-After to
// arbitrate. Base 250ms doubling per attempt, capped at 5s; a
// Retry-After delta in seconds wins when present and sane.
fn backoff_ns(attempt: int, retry_after: str) -> int {
    if retry_after != "" {
        let r = to_int(retry_after);
        if let secs = r {
            if secs >= 0 && secs <= 300 {
                return secs * 1000000000;
            }
        }
    }
    let wait = 250000000;
    let i = 1;
    while i < attempt {
        wait = wait * 2;
        i = i + 1;
    }
    if wait > 5000000000 {
        return 5000000000;
    }
    return wait;
}

// Webhook endpoints and incoming event verification.
//
// Register an endpoint, keep its `whsec_...` secret, and verify every
// delivery before parsing it. One secret per endpoint: when the handler
// moves, edit the endpoint URL instead of registering a second one.

import "json";
import "crypto";
import "encoding";
import "strings";
import "http";
import "time";
import "builder";

// An endpoint as list/get returns it. `secret` is never included.
pub gc struct WebhookEndpoint {
    id: str,
    url: str,
    events: EventFilter,
    disabled: bool,
    disabled_at: opt[str],
    consecutive_failures: int,
    auto_disabled: bool,
    pending_deliveries: int,
    created_at: str,
    updated_at: opt[str]
}

// Which event types an endpoint receives. `all` (subscribe to every
// event type) versus an explicit list.
pub gc struct EventFilter {
    all: bool,
    events: [str]
}

// An endpoint filter for every event type.
pub fn all_events() -> EventFilter {
    let none_names: [str] = [];
    return EventFilter { all: true, events: none_names };
}

// An endpoint filter for exactly these event names.
pub fn some_events(names: [str]) -> EventFilter {
    return EventFilter { all: false, events: names };
}

// Wire shape of an endpoint: `events` arrives as the string "all" or
// an array of names, which no single struct field can decode, so
// `normalize_events` flattens it to one string before decoding.
gc struct WireEndpoint {
    id: str,
    url: str,
    events: str,
    disabled: bool,
    disabled_at: opt[str],
    consecutive_failures: int,
    auto_disabled: bool,
    pending_deliveries: int,
    created_at: str,
    updated_at: opt[str]
}

gc struct WireEndpointWithSecret {
    id: str,
    url: str,
    events: str,
    disabled: bool,
    disabled_at: opt[str],
    consecutive_failures: int,
    auto_disabled: bool,
    pending_deliveries: int,
    created_at: str,
    updated_at: opt[str],
    secret: str
}

// Create/update responses also carry the signing secret, shown once.
pub gc struct WebhookEndpointWithSecret {
    id: str,
    url: str,
    events: EventFilter,
    disabled: bool,
    disabled_at: opt[str],
    consecutive_failures: int,
    auto_disabled: bool,
    pending_deliveries: int,
    created_at: str,
    updated_at: opt[str],
    secret: str
}

// One delivery of an event to an endpoint.
pub gc struct WebhookDelivery {
    id: str,
    replay_of: opt[str],
    status: str,
    created_at: str
}

pub gc struct WebhookList {
    data: [WebhookEndpoint]
}

// List decode target: endpoints with the flat-string events form that
// normalize_events produces; converted element-wise after decoding.
gc struct WebhookListFlat {
    data: [WireEndpoint]
}

pub gc struct DeliveryList {
    data: [WebhookDelivery]
}

// An inbound event. `data` carries every documented string field of
// every event type; numeric/boolean/nested values are dropped and
// unknown keys ignored, so one decode covers all current and future
// event shapes without ever failing on them.
pub gc struct Event {
    type: str,
    created_at: str,
    data: EventData
}

pub gc struct EventData {
    email_id: opt[str],
    domain: opt[str],
    url: opt[str],
    message_id: opt[str],
    smtp_response: opt[str],
    bounce_type: opt[str],
    reason: opt[str],
    status: opt[str],
    address: opt[str],
    detail: opt[str],
    removed: opt[int],
    score: opt[int],
    from: opt[str],
    recipients: opt[[str]],
    subject: opt[str],
    tag: opt[str],
    thread_id: opt[str],
    in_reply_to_email_id: opt[str]
}

// Register an endpoint. `events` none subscribes to every event type;
// otherwise pass the exact names (email.delivered, ...).
pub fn create_webhook(c: Client, url: str, events: opt[[str]],
                      deadline: until)
        -> result[WebhookEndpointWithSecret, ApiError] {
    let rr = do_json(c, "POST", "/v1/webhooks",
                     some(json.encode(WebhookRequest {
                         url: url, events: events
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_endpoint_secret(raw.body);
}

// List all endpoints.
pub fn list_webhooks(c: Client, deadline: until)
        -> result[[WebhookEndpoint], ApiError] {
    let rr = do_json(c, "GET", "/v1/webhooks", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[WebhookListFlat, str] = json.decode(normalize_events(raw.body));
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    let out: [WebhookEndpoint] = [];
    for i in 0..len(page.data) {
        push(out, to_endpoint(page.data[i]));
    }
    return ok(out);
}

// Change an endpoint's URL (keeps its secret and pending deliveries)
// and optionally re-enable it.
pub fn update_webhook(c: Client, id: str, url: str, enable: opt[bool],
                      deadline: until) -> result[WebhookEndpoint, ApiError] {
    let rr = do_json(c, "PATCH", "/v1/webhooks/" + id,
                     some(json.encode(WebhookUpdate {
                         url: url, enable: enable
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_endpoint(raw.body);
}

// Delete an endpoint. `permanent` true removes its history as well.
pub fn delete_webhook(c: Client, id: str, permanent: opt[bool],
                      deadline: until) -> result[bool, ApiError] {
    let q = query_of([query_opt_bool("permanent", permanent)]);
    let rr = do_json(c, "DELETE", "/v1/webhooks/" + id + q, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(true);
}

// Stop deliveries without deleting the endpoint or its secret.
pub fn disable_webhook(c: Client, id: str, deadline: until)
        -> result[WebhookEndpoint, ApiError] {
    let rr = do_json(c, "POST", "/v1/webhooks/" + id + "/disable", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_endpoint(raw.body);
}

// Resume a disabled endpoint.
pub fn enable_webhook(c: Client, id: str, deadline: until)
        -> result[WebhookEndpoint, ApiError] {
    let rr = do_json(c, "POST", "/v1/webhooks/" + id + "/enable", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_endpoint(raw.body);
}

// Issue a new signing secret. The old one dies with this call, so
// store the returned secret before deploying anything that needs it.
pub fn rotate_webhook_secret(c: Client, id: str, deadline: until)
        -> result[WebhookEndpointWithSecret, ApiError] {
    let rr = do_json(c, "POST", "/v1/webhooks/" + id + "/rotate-secret",
                     none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_endpoint_secret(raw.body);
}

// Delivery history for one endpoint.
pub fn list_webhook_deliveries(c: Client, id: str, deadline: until)
        -> result[[WebhookDelivery], ApiError] {
    let rr = do_json(c, "GET", "/v1/webhooks/" + id + "/deliveries", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[DeliveryList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Re-fire a past delivery as a NEW delivery (new id, traceable via
// replay_of). Returns the new delivery.
pub fn replay_webhook_delivery(c: Client, delivery_id: str, deadline: until)
        -> result[WebhookDelivery, ApiError] {
    let rr = do_json(c, "POST", "/v1/webhooks/deliveries/" + delivery_id
                     + "/replay", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[WebhookDelivery, str] = json.decode(raw.body);
    guard let d = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(d);
}

// Verify an inbound delivery: parse `t=<unix>,v1=<hex>` from the
// sendbyte-signature header, reject stale timestamps (default 300s),
// and HMAC-SHA256 `"<t>.<raw body>"` with a constant-time compare.
// Always verify the RAW body before parsing it as JSON.
pub fn verify_signature(secret: str, header: str, body: bytes) -> bool {
    return verify_signature_at(secret, header, body, 300,
                               time_wall_secs());
}

// Same check with explicit tolerance and clock: deterministic, for
// tests and for handlers with their own time source.
pub fn verify_signature_at(secret: str, header: str, body: bytes,
                           tolerance_secs: int, now_secs: int) -> bool {
    guard let t = signature_part(header, "t=") else {
        return false;
    }
    guard let hex = signature_part(header, "v1=") else {
        return false;
    }
    let tr = to_int(t);
    guard let stamp = tr else {
        return false;
    }
    if stamp < 0 {
        return false;
    }
    let age = now_secs - stamp;
    if age < 0 {
        return false;
    }
    if age > tolerance_secs {
        return false;
    }
    let signed = to_bytes(to_str(stamp) + "." + to_str(body));
    let mac = crypto.hmac_sha256(to_bytes(secret), signed);
    return hmac_equal_hex(mac, hex);
}

// Decode a verified body into an Event. Fails closed on malformed JSON
// or on a body whose envelope is missing type/created_at.
pub fn decode_event(body: bytes) -> result[Event, str] {
    let r: result[Event, str] = json.decode(to_str(body));
    guard let ev = r else let e = err_of(r) {
        return err("sendbyte: bad event body: " + e);
    }
    return ok(ev);
}

// One call for zokor (or plain http) handlers: verify the request's
// signature against `secret`, then decode its event. The body comes
// straight off req.body, never re-serialized.
//
//     fn hook(c: zokor.Ctx[App]) -> http.Response {
//         let wr = sendbyte.webhook_request(secrets.sendbyte_whsec,
//                                            c.req);
//         guard let ev = wr else let e = err_of(wr) {
//             return zokor.text(401, "bad signature: " + e);
//         }
//         ...
//     }
pub fn webhook_request(secret: str, req: http.Request)
        -> result[Event, str] {
    guard let header = http.header(req, "sendbyte-signature") else {
        return err("sendbyte: missing sendbyte-signature header");
    }
    if !verify_signature(secret, header, req.body) {
        return err("sendbyte: signature mismatch (wrong secret, stale timestamp, or tampered body)");
    }
    return decode_event(req.body);
}

// The `t=` / `v1=` part of a `t=..,v1=..` signature header.
fn signature_part(header: str, prefix: str) -> opt[str] {
    let parts = strings.split(header, ",");
    for i in 0..len(parts) {
        let part = strings.trim(parts[i]);
        if strings.has_prefix(part, prefix) {
            return some(strings.slice(part, len(prefix), len(part)));
        }
    }
    return none;
}

// Constant-time hex compare over the raw digest: accumulate every byte
// difference with OR so the loop never exits early on content.
fn hmac_equal_hex(mac: bytes, hex: str) -> bool {
    let want = to_bytes(encoding.hex_encode(mac));
    let have = to_bytes(hex);
    if len(want) != len(have) {
        return false;
    }
    let diff = 0;
    for i in 0..len(want) {
        if want[i] != have[i] {
            diff = diff | 1;
        }
    }
    return diff == 0;
}

fn time_wall_secs() -> int {
    return time.wall() / 1000000000;
}

gc struct WebhookRequest {
    url: str,
    events: opt[[str]]
}

gc struct WebhookUpdate {
    url: str,
    enable: opt[bool]
}

fn decode_endpoint(body: str) -> result[WebhookEndpoint, ApiError] {
    let r: result[WireEndpoint, str] = json.decode(normalize_events(body));
    guard let e = r else let er = err_of(r) {
        return err(ApiError { code: "decode_error", message: er, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(to_endpoint(e));
}

fn decode_endpoint_secret(body: str)
        -> result[WebhookEndpointWithSecret, ApiError] {
    let r: result[WireEndpointWithSecret, str] =
        json.decode(normalize_events(body));
    guard let e = r else let er = err_of(r) {
        return err(ApiError { code: "decode_error", message: er, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(to_endpoint_secret(e));
}

fn to_endpoint(w: WireEndpoint) -> WebhookEndpoint {
    return WebhookEndpoint {
        id: w.id, url: w.url, events: parse_event_filter(w.events),
        disabled: w.disabled, disabled_at: w.disabled_at,
        consecutive_failures: w.consecutive_failures,
        auto_disabled: w.auto_disabled, pending_deliveries: w.pending_deliveries,
        created_at: w.created_at, updated_at: w.updated_at
    };
}

fn to_endpoint_secret(w: WireEndpointWithSecret) -> WebhookEndpointWithSecret {
    return WebhookEndpointWithSecret {
        id: w.id, url: w.url, events: parse_event_filter(w.events),
        disabled: w.disabled, disabled_at: w.disabled_at,
        consecutive_failures: w.consecutive_failures,
        auto_disabled: w.auto_disabled, pending_deliveries: w.pending_deliveries,
        created_at: w.created_at, updated_at: w.updated_at, secret: w.secret
    };
}

// Parse a flattened events string: "all", "", or "a,b,c".
pub fn parse_event_filter(flat: str) -> EventFilter {
    if flat == "all" {
        return all_events();
    }
    if flat == "" {
        return some_events([]);
    }
    let out: [str] = [];
    for part in strings.split(flat, ",") {
        let name = strings.trim(part);
        if name != "" {
            push(out, name);
        }
    }
    return some_events(out);
}

// Rewrite every `"events": <string|array>` value in a response body to
// the flat string form `parse_event_filter` reads: `"all"` stays, while
// `["a", "b"]` becomes `"a,b"`. The scanner honors JSON strings (so
// brackets inside quoted values never confuse it) and any whitespace
// around tokens. Only the documented shapes occur on this wire.
// Byte codes used by the scanner below. JSON structure is ASCII, so
// byte offsets are exact.
fn b_quote() -> int {
    return 34;
}

fn b_backslash() -> int {
    return 92;
}

fn b_lbracket() -> int {
    return 91;
}

fn b_rbracket() -> int {
    return 93;
}

fn b_colon() -> int {
    return 58;
}

fn b_comma() -> int {
    return 44;
}

// Rewrite every `"events": <string|array>` value in a response body to
// the flat string form `parse_event_filter` reads: `"all"` stays, while
// `["a", "b"]` becomes `"a,b"`. Works on bytes (str cannot be indexed)
// and honors JSON strings, so brackets inside quoted values never
// confuse it, at any whitespace layout. Only the documented shapes
// occur on this wire.
pub fn normalize_events(body: str) -> str {
    let src = to_bytes(body);
    let out = builder.new_bytes();
    let i = 0;
    while i < len(src) {
        let key_at = find_key_at(src, i);
        if key_at < 0 {
            out = out.write(src[i..]);
            break;
        }
        out = out.write(src[i..key_at]);
        let v = read_json_value(src, key_at + 8);
        out = out.write(to_bytes("\"events\":"));
        out = out.write(v.value);
        i = v.next;
    }
    return to_str(out.finish());
}

gc struct JsonValue {
    value: bytes,
    next: int
}

// Locate `"events"` used as an object key at or after `from`: returns
// the offset of the opening quote, or -1. A key is a quoted string
// directly followed (mod whitespace) by a colon.
fn find_key_at(src: bytes, from: int) -> int {
    let key = to_bytes("\"events\"");
    let i = from;
    while i < len(src) {
        let q = find_byte(src, i, b_quote());
        if q < 0 {
            return -1;
        }
        let end = scan_string_end(src, q);
        if end < 0 {
            return -1;
        }
        if slice_eq(src, q, end + 1, key) {
            let c = skip_ws(src, end + 1);
            if c < len(src) && src[c] == b_colon() {
                return q;
            }
        }
        i = end + 1;
    }
    return -1;
}

// Read one JSON value starting just past the `"events"` key: skips the
// colon, then returns replacement bytes plus next offset. Strings pass
// through verbatim; string arrays flatten to a quoted comma-joined
// string; anything else passes its first byte through and lets the
// decoder report the shape instead of silently mangling data.
fn read_json_value(src: bytes, at: int) -> JsonValue {
    let i = skip_ws(src, at);
    if i < len(src) && src[i] == b_colon() {
        i = skip_ws(src, i + 1);
    }
    if i >= len(src) {
        return JsonValue { value: b"", next: i };
    }
    if src[i] == b_quote() {
        let end = scan_string_end(src, i);
        if end < 0 {
            return JsonValue { value: src[i..], next: len(src) };
        }
        return JsonValue { value: src[i..end + 1], next: end + 1 };
    }
    if src[i] == b_lbracket() {
        return flatten_string_array(src, i);
    }
    return JsonValue { value: src[i..i + 1], next: i + 1 };
}

// Flatten a `["a", "b"]` array (strings only) to `"a,b"`. Stops at the
// closing bracket; anything unexpected passes its source through.
fn flatten_string_array(src: bytes, at: int) -> JsonValue {
    let b = builder.new_bytes();
    b = b.write_byte(b_quote());
    let i = skip_ws(src, at + 1);
    let first = true;
    while i < len(src) {
        if src[i] == b_rbracket() {
            b = b.write_byte(b_quote());
            return JsonValue { value: b.finish(), next: i + 1 };
        }
        if src[i] == b_comma() {
            i = skip_ws(src, i + 1);
            continue;
        }
        if src[i] == b_quote() {
            let end = scan_string_end(src, i);
            if end < 0 {
                b = b.write_byte(b_quote());
                return JsonValue { value: b.finish(), next: len(src) };
            }
            if !first {
                b = b.write_byte(b_comma());
            }
            first = false;
            b = b.write(src[i + 1..end]);
            i = skip_ws(src, end + 1);
            continue;
        }
        return JsonValue { value: src[at..at + 1], next: at + 1 };
    }
    b = b.write_byte(b_quote());
    return JsonValue { value: b.finish(), next: len(src) };
}

// Offset just past the closing quote of the string opened at `at`
// (which must be `"`), honoring backslash escapes; -1 if unterminated.
fn scan_string_end(src: bytes, at: int) -> int {
    let i = at + 1;
    while i < len(src) {
        if src[i] == b_backslash() {
            i = i + 2;
            continue;
        }
        if src[i] == b_quote() {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

// True when src[a..b] holds exactly `want`.
fn slice_eq(src: bytes, a: int, b: int, want: bytes) -> bool {
    if b - a != len(want) {
        return false;
    }
    for i in 0..len(want) {
        if src[a + i] != want[i] {
            return false;
        }
    }
    return true;
}

// First offset at/after `from` holding byte `ch`, or -1.
fn find_byte(src: bytes, from: int, ch: int) -> int {
    let i = from;
    while i < len(src) {
        if src[i] == ch {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

// First offset at/after `from` that is not JSON whitespace, or len.
fn skip_ws(src: bytes, from: int) -> int {
    let i = from;
    while i < len(src) {
        if src[i] == 32 || src[i] == 9 || src[i] == 10 || src[i] == 13 {
            i = i + 1;
            continue;
        }
        break;
    }
    return i;
}

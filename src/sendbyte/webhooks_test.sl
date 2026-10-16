// Offline unit tests: signature verification, event decoding, and the
// events normalizer. No network, no keys, fully deterministic.

import "crypto";
import "encoding";
import "strings";
import "json";

// Build a valid `t=..,v1=..` header for fixed inputs using the same
// primitives the verifier uses: this pins the parsing, timestamp, and
// comparison logic (the HMAC itself is slang's crypto).
fn good_header(secret: str, t: int, body: bytes) -> str {
    let mac = crypto.hmac_sha256(to_bytes(secret),
                                 to_bytes(to_str(t) + "." + to_str(body)));
    return "t=" + to_str(t) + ",v1=" + encoding.hex_encode(mac);
}

fn test_verify_accepts_valid_signature() {
    let body = to_bytes("{\"type\":\"email.delivered\"}");
    let h = good_header("whsec_abc", 1700000000, body);
    assert(verify_signature_at("whsec_abc", h, body, 300, 1700000100));
}

fn test_verify_rejects_wrong_secret() {
    let body = to_bytes("{\"type\":\"email.delivered\"}");
    let h = good_header("whsec_abc", 1700000000, body);
    assert(!verify_signature_at("whsec_nope", h, body, 300, 1700000100));
}

fn test_verify_rejects_tampered_body() {
    let body = to_bytes("{\"type\":\"email.delivered\"}");
    let h = good_header("whsec_abc", 1700000000, body);
    let other = to_bytes("{\"type\":\"email.bounced\"}");
    assert(!verify_signature_at("whsec_abc", h, other, 300, 1700000100));
}

fn test_verify_rejects_stale_timestamp() {
    let body = to_bytes("{}");
    let h = good_header("whsec_abc", 1700000000, body);
    assert(!verify_signature_at("whsec_abc", h, body, 300, 1700000401));
    assert(verify_signature_at("whsec_abc", h, body, 300, 1700000300));
}

fn test_verify_rejects_malformed_headers() {
    let body = to_bytes("{}");
    assert(!verify_signature_at("s", "", body, 300, 1));
    assert(!verify_signature_at("s", "v1=abc", body, 300, 1));
    assert(!verify_signature_at("s", "t=xyz,v1=abc", body, 300, 1));
    assert(!verify_signature_at("s", "t=-5,v1=abc", body, 300, 1));
}

fn test_normalize_all_shape() {
    assert(parse_event_filter("all").all);
    assert(normalize_events("{\"events\": \"all\"}") == "{\"events\":\"all\"}");
}

fn test_normalize_array_shape() {
    let flat = normalize_events("{\"events\": [\"email.delivered\", \"email.bounced\"] }");
    let f = parse_event_filter(flat_content(flat));
    assert(!f.all);
    assert(len(f.events) == 2);
    assert(f.events[0] == "email.delivered");
}

fn test_normalize_compact_array() {
    let flat = normalize_events("{\"events\":[\"email.clicked\"]}");
    let f = parse_event_filter(flat_content(flat));
    assert(!f.all);
    assert(len(f.events) == 1);
}

// Brackets inside quoted strings must not confuse the scanner.
fn test_normalize_ignores_brackets_in_strings() {
    let body = "{\"note\": \"a [bracketed] value\", \"events\": [\"x\"]}";
    let f = parse_event_filter(flat_content(normalize_events(body)));
    assert(!f.all);
    assert(len(f.events) == 1);
    assert(f.events[0] == "x");
}

// The `"events": <flat>` value out of a normalized single-key body,
// for testing the normalizer without a full endpoint decode.
fn flat_content(normalized: str) -> str {
    let parts = strings.split(normalized, ":");
    let last = strings.trim(parts[len(parts) - 1]);
    return strings.slice(last, 1, len(last) - 2);
}

// Decode a documented bounced payload verbatim: ints and bools in
// `data` must not break decoding of the string fields.
fn test_decode_bounced_event() {
    let body = "{\"type\": \"email.bounced\", \"created_at\": \"2024-01-15T10:05:32Z\", \"data\": {\"email_id\": \"em_8f2a91c4\", \"bounce_type\": \"hard\", \"smtp_code\": 550, \"smtp_response\": \"550 nope\", \"rejected\": true}}";
    let rr1 = decode_event(to_bytes(body));
    guard let ev = rr1 else let e = err_of(rr1) {
        assert(false, "decode failed: " + e);
        return;
    }
    assert(ev.type == "email.bounced");
    guard let id = ev.data.email_id else {
        assert(false, "missing email_id");
        return;
    }
    assert(id == "em_8f2a91c4");
    guard let bt = ev.data.bounce_type else {
        assert(false, "missing bounce_type");
        return;
    }
    assert(bt == "hard");
}

fn test_decode_clicked_and_verified_events() {
    let clicked = "{\"type\": \"email.clicked\", \"created_at\": \"2024-01-15T10:12:08Z\", \"data\": {\"email_id\": \"em_1\", \"url\": \"https://x.example/confirm\"}}";
    let rr2 = decode_event(to_bytes(clicked));
    guard let ev = rr2 else let e = err_of(rr2) {
        assert(false, "decode failed: " + e);
        return;
    }
    guard let u = ev.data.url else {
        assert(false, "missing url");
        return;
    }
    assert(u == "https://x.example/confirm");
    let verified = "{\"type\": \"domain.verified\", \"created_at\": \"2024-01-15T09:30:00Z\", \"data\": {\"domain\": \"receipts.paylink.ng\"}}";
    let rr3 = decode_event(to_bytes(verified));
    guard let dv = rr3 else let e = err_of(rr3) {
        assert(false, "decode failed: " + e);
        return;
    }
    guard let d = dv.data.domain else {
        assert(false, "missing domain");
        return;
    }
    assert(d == "receipts.paylink.ng");
}

fn test_endpoint_decodes_both_event_shapes() {
    let all = "{\"id\": \"1\", \"url\": \"https://x.example/h\", \"events\": \"all\", \"disabled\": false, \"consecutive_failures\": 0, \"auto_disabled\": false, \"pending_deliveries\": 0, \"created_at\": \"2024-01-15T10:00:00Z\"}";
    let rr4 = decode_endpoint(all);
    guard let a = rr4 else let e = err_of(rr4) {
        assert(false, "decode failed: " + error_string(e));
        return;
    }
    assert(a.events.all);
    let some = "{\"id\": \"2\", \"url\": \"https://x.example/h\", \"events\": [\"email.delivered\"], \"disabled\": false, \"consecutive_failures\": 0, \"auto_disabled\": false, \"pending_deliveries\": 0, \"created_at\": \"2024-01-15T10:00:00Z\"}";
    let rr5 = decode_endpoint(some);
    guard let b = rr5 else let e = err_of(rr5) {
        assert(false, "decode failed: " + error_string(e));
        return;
    }
    assert(!b.events.all);
    assert(len(b.events.events) == 1);
}

fn test_mixed_list_decodes() {
    let body = "{\"data\": [{\"id\": \"1\", \"url\": \"https://x.example/h\", \"events\": \"all\", \"disabled\": false, \"consecutive_failures\": 0, \"auto_disabled\": false, \"pending_deliveries\": 0, \"created_at\": \"2024-01-15T10:00:00Z\"}, {\"id\": \"2\", \"url\": \"https://x.example/h\", \"events\": [\"email.bounced\"], \"disabled\": true, \"consecutive_failures\": 3, \"auto_disabled\": false, \"pending_deliveries\": 1, \"created_at\": \"2024-01-15T10:00:00Z\"}]}";
    let r: result[WebhookListFlat, str] = json.decode(normalize_events(body));
    guard let page = r else let e = err_of(r) {
        assert(false, "decode failed: " + e);
        return;
    }
    assert(len(page.data) == 2);
    let a = to_endpoint(page.data[0]);
    let b = to_endpoint(page.data[1]);
    assert(a.events.all);
    assert(!b.events.all);
}

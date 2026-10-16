// Offline unit tests: key validation, error decoding, query builders.
// No network, no keys, fully deterministic.

import "json";
import "time";

fn test_key_constructors() {
    let r = new_client("sk_test_abc");
    guard let c = r else let e = err_of(r) {
        assert(false, "new_client rejected a key: " + e);
        return;
    }
    assert(!is_live_key("sk_test_abc"), "test key reads live");
    assert(is_test_key("sk_test_abc"), "test key not recognized");
    assert(is_live_key("sk_live_xyz"), "live key not recognized");
    let rt = new_test_client("sk_test_abc");
    guard let t = rt else let e = err_of(rt) {
        assert(false, "test client rejected: " + e);
        return;
    }
    let rl = new_live_client("sk_live_xyz");
    guard let l = rl else let e = err_of(rl) {
        assert(false, "live client rejected: " + e);
        return;
    }
    assert(c.base == "https://api.sendbyte.africa", "bad default base");
    assert(t.timeout_ns == 30000000000, "bad default timeout");
    assert(l.max_attempts == 3, "bad default attempts");
}

fn test_key_rejections() {
    let r1 = new_client("");
    guard let _c1 = r1 else {
        return;
    }
    assert(false, "empty key accepted");
}

fn test_wrong_family_rejected() {
    let r1 = new_test_client("sk_live_xyz");
    guard let _c1 = r1 else {
        return;
    }
    assert(false, "live key accepted as test");
}

fn test_live_rejects_test() {
    let r1 = new_live_client("sk_test_abc");
    guard let _c1 = r1 else {
        return;
    }
    assert(false, "test key accepted as live");
}

fn test_decode_error_envelope() {
    let e = decode_error_body(422,
        "{\"error\": {\"code\": \"suppressed_recipient\", \"message\": \"nope\", \"docs_url\": \"https://x.example/e\"}}",
        "req-1");
    assert(e.code == "suppressed_recipient", "code: " + e.code);
    assert(e.status == 422, "status");
    assert(e.request_id == "req-1", "request id");
    assert(e.docs_url == "https://x.example/e", "docs url");
    assert(is_rate_limited(ApiError { code: "rate_limit_exceeded",
        message: "slow", docs_url: "", status: 429, request_id: "" }),
        "rate limit not detected");
    assert(!is_rate_limited(e), "false rate limit");
    assert(error_string(e) == "sendbyte.suppressed_recipient (status 422, request req-1): nope",
        "error string: " + error_string(e));
}

fn test_decode_error_fallback() {
    let e = decode_error_body(502, "<html>bad gateway</html>", "req-2");
    assert(e.code == "request_failed", "code: " + e.code);
    assert(e.status == 502, "status");
}

fn test_query_builders() {
    assert(query_of([]) == "", "empty");
    assert(query_int("limit", 50) == "limit=50", "int");
    assert(query_int("limit", 0) == "", "zero int");
    assert(query_opt("status", some("delivered")) == "status=delivered",
        "opt some");
    assert(query_opt("after", none) == "", "opt none");
    assert(query_opt_bool("sandbox", some(true)) == "sandbox=true",
        "bool true");
    assert(query_opt_bool("x", some(false)) == "x=false", "bool false");
    assert(query_opt_bool("x", none) == "", "bool none");
    assert(query_pair("q", "a%20b") == "q=a%20b", "pair passthrough");
}

fn test_query_of_joins() {
    let q = query_of([query_int("limit", 50),
                      query_opt("status", some("delivered")),
                      query_opt("after", none)]);
    assert(q == "?limit=50&status=delivered", "joined: " + q);
}

fn test_deadline_in_future() {
    assert(deadline_in(30) != deadline_in(0), "deadlines do not advance");
    assert(deadline_in(30) != until_never(), "deadline is never");
}

fn test_send_request_round_trip() {
    let req = new_email("You <you@yourapp.ng>", to_one("a@example.ng"));
    req.subject = some("hi");
    req.html = some("<p>hi</p>");
    req.idempotency_key = some("order-1");
    let body = json.encode(req);
    let r: result[SendEmailRequest, str] = json.decode(body);
    guard let back = r else let e = err_of(r) {
        assert(false, "round trip failed: " + e);
        return;
    }
    assert(back.from == "You <you@yourapp.ng>", "from");
    assert(len(back.to) == 1, "to len");
    assert(back.to[0] == "a@example.ng", "to[0]");
    guard let s = back.subject else {
        assert(false, "subject lost");
        return;
    }
    assert(s == "hi", "subject");
    guard let k = back.idempotency_key else {
        assert(false, "key lost");
        return;
    }
    assert(k == "order-1", "key");
    assert(len(back.tags) == 0, "tags default");
}

fn test_to_one_and_attachment() {
    assert(len(to_one("a@b.ng")) == 1, "to_one len");
    let a = attachment("hello.txt", "text/plain", to_bytes("hi"));
    assert(a.filename == "hello.txt", "filename");
    assert(a.content_type == "text/plain", "content type");
    assert(a.content != "", "content empty");
}

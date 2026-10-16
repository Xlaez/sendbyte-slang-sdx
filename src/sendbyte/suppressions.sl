// Suppressions: addresses you may no longer mail, plus the
// recipient-verified self-service flow that can remove eligible ones.

import "json";
import "encoding";

// An address on the suppression list.
pub gc struct Suppression {
    address: str,
    reason: str,
    source: str,
    created_at: str,
    eligible: bool,
    eligible_reason: opt[str]
}

// A removal request moving through verify → remove (or expiry).
pub gc struct RemovalRequest {
    id: str,
    address: str,
    reason: str,
    status: str,
    note: opt[str],
    source: str,
    verification_sends: int,
    verification_failed: bool,
    created_at: str,
    expires_at: opt[str],
    verified_at: opt[str],
    removed_at: opt[str],
    cancelled_at: opt[str]
}

pub gc struct SuppressionList {
    data: [Suppression]
}

pub gc struct RemovalList {
    data: [RemovalRequest]
}

// List suppressed addresses. `search` narrows by address substring,
// `limit` 0 takes the server default.
pub fn list_suppressions(c: Client, search: opt[str], limit: int,
                         deadline: until)
        -> result[[Suppression], ApiError] {
    let q = query_of([
        query_opt("search", search),
        query_int("limit", limit)
    ]);
    let rr = do_json(c, "GET", "/v1/suppressions" + q, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[SuppressionList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Look up one address. A missing entry is a not_found ApiError, which
// usefully doubles as "safe to send".
pub fn get_suppression(c: Client, address: str, deadline: until)
        -> result[Suppression, ApiError] {
    let rr = do_json(c, "GET", "/v1/suppressions/" + encoding.url_encode(address),
                     none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[Suppression, str] = json.decode(raw.body);
    guard let s = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(s);
}

// Ask SendByte to start recipient-verified removal. Only eligible
// addresses (see Suppression.eligible) can start this flow.
pub fn request_suppression_removal(c: Client, address: str, note: opt[str],
                                   deadline: until)
        -> result[RemovalRequest, ApiError] {
    let rr = do_json(c, "POST", "/v1/suppressions/removals",
                     some(json.encode(RemovalAsk {
                         address: address, note: note
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_removal(raw.body);
}

// List removal requests, newest first.
pub fn list_suppression_removals(c: Client, deadline: until)
        -> result[[RemovalRequest], ApiError] {
    let rr = do_json(c, "GET", "/v1/suppressions/removals", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[RemovalList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Fetch one removal request by id.
pub fn get_suppression_removal(c: Client, id: str, deadline: until)
        -> result[RemovalRequest, ApiError] {
    let rr = do_json(c, "GET", "/v1/suppressions/removals/" + id, none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_removal(raw.body);
}

// Withdraw a pending removal request.
pub fn cancel_suppression_removal(c: Client, id: str, deadline: until)
        -> result[bool, ApiError] {
    let rr = do_json(c, "DELETE", "/v1/suppressions/removals/" + id, none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(true);
}

// Re-send the recipient's confirmation email for a pending request.
// SendByte also retries automatically; call this when the recipient
// says the mail never arrived.
pub fn resend_suppression_removal(c: Client, id: str, deadline: until)
        -> result[RemovalRequest, ApiError] {
    let rr = do_json(c, "POST", "/v1/suppressions/removals/" + id + "/resend",
                     none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_removal(raw.body);
}

gc struct RemovalAsk {
    address: str,
    note: opt[str]
}

fn decode_removal(body: str) -> result[RemovalRequest, ApiError] {
    let r: result[RemovalRequest, str] = json.decode(body);
    guard let q = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(q);
}

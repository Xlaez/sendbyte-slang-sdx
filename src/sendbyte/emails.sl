// Send and read transactional email.
//
// Address lists are always `[str]`, sending and receiving: the API
// normalizes a lone address to a one-element array (mirroring the Go
// SDK's `[]string`), so one shape covers both directions.

import "json";
import "builder";
import "encoding";

// One attachment. Build with `attachment()` (it base64-encodes `data`)
// rather than filling `content` by hand.
pub gc struct Attachment {
    filename: str,
    content: str,
    content_type: str,
    content_id: opt[str],
    disposition: opt[str]
}

// Per-message open/click tracking override. `none` everywhere defers to
// the domain defaults.
pub gc struct Tracking {
    opens: opt[bool],
    clicks: opt[bool]
}

pub gc struct ListUnsubscribe {
    url: opt[str],
    mailto: opt[str]
}

// Everything POST /v1/emails accepts. Only `from` and `to` are always
// required: give `subject` plus `html`/`text`, or a `template_id` (with
// optional `variables`). Unset optionals encode as explicit JSON nulls,
// which the API reads as absent.
pub gc struct SendEmailRequest {
    from: str,
    to: [str],
    subject: opt[str],
    html: opt[str],
    text: opt[str],
    template_id: opt[str],
    variables: map[str]str,
    cc: [str],
    bcc: [str],
    reply_to: [str],
    attachments: [Attachment],
    tags: [str],
    headers: map[str]str,
    list_unsubscribe: opt[ListUnsubscribe],
    scheduled_at: opt[str],
    idempotency_key: opt[str],
    tracking: opt[Tracking]
}

// A sent email as GET returns it.
pub gc struct Email {
    id: str,
    from: str,
    to: [str],
    subject: str,
    status: str,
    sandbox: bool,
    tags: [str],
    message_id: opt[str],
    open_count: int,
    click_count: int,
    first_opened_at: opt[str],
    first_clicked_at: opt[str],
    scheduled_at: opt[str],
    created_at: str
}

// One timeline entry on an email's detail view: what happened and
// when. The entry's `payload` object is deliberately not decoded (its
// values mix strings, numbers, and booleans); the event webhooks carry
// the full typed payload via Event/EventData instead.
pub gc struct EmailEvent {
    type: str,
    created_at: str
}

// GET /v1/emails/{id}: the email plus body content and event timeline.
pub gc struct EmailDetail {
    id: str,
    from: str,
    to: [str],
    subject: str,
    status: str,
    sandbox: bool,
    tags: [str],
    message_id: opt[str],
    open_count: int,
    click_count: int,
    first_opened_at: opt[str],
    first_clicked_at: opt[str],
    scheduled_at: opt[str],
    created_at: str,
    html: opt[str],
    text: opt[str],
    events: [EmailEvent]
}

// One page of GET /v1/emails.
pub gc struct EmailPage {
    data: [Email],
    has_more: bool
}

// A blank send request: fill `from`, `to`, and the body of your choice.
pub fn new_email(from: str, to: [str]) -> SendEmailRequest {
    let no_vars: map[str]str = {};
    let no_headers: map[str]str = {};
    return SendEmailRequest {
        from: from, to: to, subject: none, html: none, text: none,
        template_id: none, variables: no_vars, cc: [], bcc: [],
        reply_to: [], attachments: [], tags: [], headers: no_headers,
        list_unsubscribe: none, scheduled_at: none, idempotency_key: none,
        tracking: none
    };
}

// A single recipient as a one-element list.
pub fn to_one(addr: str) -> [str] {
    return [addr];
}

// Build an attachment from raw bytes (base64-encoded for the wire).
pub fn attachment(filename: str, content_type: str, data: bytes) -> Attachment {
    return Attachment { filename: filename, content: encoding.base64_encode(data),
                        content_type: content_type, content_id: none,
                        disposition: none };
}

// Queue a transactional email. Returns 201 on a fresh send; an
// `idempotency_key` replay returns the original email instead.
pub fn send_email(c: Client, req: SendEmailRequest, deadline: until)
        -> result[Email, ApiError] {
    let rr = do_json(c, "POST", "/v1/emails", some(json.encode(req)),
                       deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_email(raw.body);
}

// Retrieve one sent email with body content and event timeline.
pub fn get_email(c: Client, id: str, deadline: until)
        -> result[EmailDetail, ApiError] {
    let rr = do_json(c, "GET", "/v1/emails/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_email_detail(raw.body);
}

// Page through sent emails, newest first. `limit` 0 takes the server
// default; `after`/`status` narrow the window (none = unset).
pub fn list_emails(c: Client, limit: int, after: opt[str], status: opt[str],
                   deadline: until) -> result[EmailPage, ApiError] {
    let q = query_of([
        query_int("limit", limit),
        query_opt("after", after),
        query_opt("status", status)
    ]);
    let rr = do_json(c, "GET", "/v1/emails" + q, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[EmailPage, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page);
}

// Export send history as CSV (same filters as list, no paging).
// `days` 0 omits the window bound; `sandbox` none omits the filter.
pub fn export_emails(c: Client, status: opt[str], domain_id: opt[str],
                     sandbox: opt[bool], days: int, search: opt[str],
                     deadline: until) -> result[bytes, ApiError] {
    let q = query_of([
        query_opt("status", status),
        query_opt("domain_id", domain_id),
        query_opt_bool("sandbox", sandbox),
        query_int("days", days),
        query_opt("search", search)
    ]);
    return do_bytes(c, "GET", "/v1/emails/export" + q, deadline);
}

fn decode_email(body: str) -> result[Email, ApiError] {
    let r: result[Email, str] = json.decode(body);
    guard let email = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(email);
}

fn decode_email_detail(body: str) -> result[EmailDetail, ApiError] {
    let r: result[EmailDetail, str] = json.decode(body);
    guard let detail = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(detail);
}

// --- query helpers (also used by other resources) ---

// One `k=v` pair; value already encoded. Empty pairs render as "" and
// are dropped by query_of.
pub fn query_pair(key: str, value: str) -> str {
    if value == "" {
        return "";
    }
    return key + "=" + value;
}

pub fn query_int(key: str, value: int) -> str {
    if value == 0 {
        return "";
    }
    return key + "=" + to_str(value);
}

pub fn query_opt(key: str, value: opt[str]) -> str {
    if let v = value {
        return query_pair(key, encoding.url_encode(v));
    }
    return "";
}

pub fn query_opt_bool(key: str, value: opt[bool]) -> str {
    if let v = value {
        if v {
            return key + "=true";
        }
        return key + "=false";
    }
    return "";
}

// Join non-empty pairs into `?a=1&b=2`, or "" when there are none.
pub fn query_of(pairs: [str]) -> str {
    let b = builder.new_str();
    let first = true;
    for i in 0..len(pairs) {
        if pairs[i] == "" {
            continue;
        }
        if first {
            b = b.write("?");
            first = false;
        } else {
            b = b.write("&");
        }
        b = b.write(pairs[i]);
    }
    return b.finish();
}

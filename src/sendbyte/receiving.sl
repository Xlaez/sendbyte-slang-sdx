// Inbound email: receiving settings, routes, received messages, and
// replies. Point your domain's MX at SendByte, route by address, and
// read or answer mail through these calls (or get the same content
// pushed as `email.received` webhooks).

import "json";
import "httpc";

// Account-level receiving state.
pub gc struct ReceivingSettings {
    available: bool,
    enabled: bool,
    enabled_at: opt[str],
    quota_notice: str,
    test_host: opt[str],
    content_days: int,
    content_days_long: int,
    domains: [DomainReceiving]
}

// One domain's inbound state.
pub gc struct DomainReceiving {
    domain_id: str,
    domain: str,
    enabled: bool,
    subdomain: str,
    host: str,
    status: str,
    checked_at: opt[str]
}

// A routing rule: which inbound mail goes where.
pub gc struct InboundRoute {
    id: str,
    domain_id: opt[str],
    match_type: str,
    match_value: str,
    action: str,
    endpoint_ids: opt[[str]],
    forward_to: [str],
    allow_senders: [str],
    block_senders: [str],
    enabled: bool,
    created_at: str,
    updated_at: str
}

// A received message header view. Bodies, attachments, and thread
// context arrive on the detail view.
pub gc struct ReceivedEmail {
    id: str,
    object: opt[str],
    status: str,
    status_reason: opt[str],
    from: str,
    envelope_from: opt[str],
    to: [str],
    cc: [str],
    reply_to: [str],
    recipients: [str],
    subject: str,
    tag: opt[str],
    message_id: opt[str],
    in_reply_to: opt[str],
    references: [str],
    thread_id: opt[str],
    in_reply_to_email_id: opt[str],
    domain_id: opt[str],
    route_id: opt[str],
    size: int,
    spam: opt[str],
    virus: opt[str],
    spf: opt[str],
    dkim: opt[str],
    dmarc: opt[str],
    counted: bool,
    content_available: bool,
    content_expires_at: str,
    attachment_count: int,
    forwarded_email_ids: [str],
    action_at: opt[str],
    received_at: str
}

// Full message: headers plus bodies, attachments, route, and thread.
pub gc struct ReceivedEmailDetail {
    id: str,
    object: opt[str],
    status: str,
    status_reason: opt[str],
    from: str,
    envelope_from: opt[str],
    to: [str],
    cc: [str],
    reply_to: [str],
    recipients: [str],
    subject: str,
    tag: opt[str],
    message_id: opt[str],
    in_reply_to: opt[str],
    references: [str],
    thread_id: opt[str],
    in_reply_to_email_id: opt[str],
    domain_id: opt[str],
    route_id: opt[str],
    size: int,
    spam: opt[str],
    virus: opt[str],
    spf: opt[str],
    dkim: opt[str],
    dmarc: opt[str],
    counted: bool,
    content_available: bool,
    content_expires_at: str,
    attachment_count: int,
    forwarded_email_ids: [str],
    action_at: opt[str],
    received_at: str,
    text: opt[str],
    html: opt[str],
    stripped_text: opt[str],
    headers: [MailHeader],
    attachments: [ReceivedAttachment]
}

// One RFC 5322 header on a received message.
pub gc struct MailHeader {
    name: str,
    value: str
}

// One attachment: metadata always, content through the download URL
// (valid 24 hours) or not at all.
pub gc struct ReceivedAttachment {
    id: str,
    filename: str,
    content_type: str,
    size: int,
    content_id: opt[str],
    disposition: str,
    url: opt[str],
    url_expires_at: opt[str]
}

// One thread entry mixing sent and received mail.
pub gc struct ConversationItem {
    direction: str,
    id: str,
    subject: str,
    from: str,
    to: [str],
    status: str,
    at: str
}

pub gc struct ReceivedList {
    data: [ReceivedEmail]
}

pub gc struct RouteList {
    data: [InboundRoute]
}

pub gc struct Conversation {
    thread_id: opt[str],
    replies: int,
    data: [ConversationItem]
}

// Account receiving settings and per-domain state.
pub fn get_receiving(c: Client, deadline: until)
        -> result[ReceivingSettings, ApiError] {
    let rr = do_json(c, "GET", "/v1/receiving", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ReceivingSettings, str] = json.decode(raw.body);
    guard let s = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(s);
}

// Turn receiving on. The acknowledge flag confirms quota understanding
// and must be true (the server rejects anything else).
pub fn enable_receiving(c: Client, deadline: until)
        -> result[ReceivingSettings, ApiError] {
    let rr = do_json(c, "POST", "/v1/receiving/enable",
                     some(json.encode(QuotaAck { acknowledge_quota: true })),
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ReceivingSettings, str] = json.decode(raw.body);
    guard let s = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(s);
}

// Turn receiving off.
pub fn disable_receiving(c: Client, deadline: until)
        -> result[ReceivingSettings, ApiError] {
    let rr = do_json(c, "POST", "/v1/receiving/disable", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ReceivingSettings, str] = json.decode(raw.body);
    guard let s = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(s);
}

// Send a probe message through the inbound pipeline to an address.
pub fn send_receiving_test(c: Client, to: str, deadline: until)
        -> result[bool, ApiError] {
    let rr = do_json(c, "POST", "/v1/receiving/test",
                     some(json.encode(TestSend { to: to })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(true);
}

// Enable receiving for one domain.
pub fn enable_domain_receiving(c: Client, id: str, deadline: until)
        -> result[DomainReceiving, ApiError] {
    let rr = do_json(c, "POST", "/v1/domains/" + id + "/receiving", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain_receiving(raw.body);
}

// Disable receiving for one domain.
pub fn disable_domain_receiving(c: Client, id: str, deadline: until)
        -> result[DomainReceiving, ApiError] {
    let rr = do_json(c, "DELETE", "/v1/domains/" + id + "/receiving", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain_receiving(raw.body);
}

// Recheck one domain's MX wiring.
pub fn check_domain_receiving(c: Client, id: str, deadline: until)
        -> result[DomainReceiving, ApiError] {
    let rr = do_json(c, "POST", "/v1/domains/" + id + "/receiving/check",
                     none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain_receiving(raw.body);
}

// Dry-run what a domain's receiving setup would do.
pub fn preflight_domain_receiving(c: Client, id: str, deadline: until)
        -> result[DomainReceiving, ApiError] {
    let rr = do_json(c, "GET", "/v1/domains/" + id + "/receiving/preflight",
                     none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain_receiving(raw.body);
}

// List received messages, newest first.
pub fn list_received_emails(c: Client, deadline: until)
        -> result[[ReceivedEmail], ApiError] {
    let rr = do_json(c, "GET", "/v1/received", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ReceivedList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// A fresh download link for one attachment (valid 24 hours).
pub gc struct AttachmentLink {
    url: str,
    filename: str,
    content_type: str,
    expires_at: str
}
// Aggregate received-mail counters. The exact shape is undocumented,
// so this returns the raw body; parse what you need from it.
pub fn received_email_stats(c: Client, deadline: until)
        -> result[str, ApiError] {
    let rr = do_json(c, "GET", "/v1/received/stats", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(raw.body);
}

// Full message with bodies, attachments, route, and thread.
pub fn get_received_email(c: Client, id: str, deadline: until)
        -> result[ReceivedEmailDetail, ApiError] {
    let rr = do_json(c, "GET", "/v1/received/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ReceivedEmailDetail, str] = json.decode(raw.body);
    guard let m = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(m);
}

// A fresh 24-hour download link for one attachment: fetch it, then
// download the bytes yourself (or hand the URL to the recipient).
pub fn get_received_attachment(c: Client, id: str, attachment_id: str,
                               deadline: until)
        -> result[AttachmentLink, ApiError] {
    let rr = do_json(c, "GET", "/v1/received/" + id + "/attachments/"
                     + attachment_id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[AttachmentLink, str] = json.decode(raw.body);
    guard let l = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(l);
}

// Download attachment bytes from a link (no auth needed: the URL is
// pre-signed). Follows the client's redirect budget.
pub fn download_attachment(c: Client, file: AttachmentLink, deadline: until)
        -> result[bytes, ApiError] {
    let rr = httpc.client_get(c.http, file.url, deadline);
    guard let resp = rr else let e = err_of(rr) {
        return err(ApiError { code: "request_failed", message: e,
                              docs_url: "", status: 0, request_id: "" });
    }
    if resp.status >= 200 && resp.status < 300 {
        return ok(resp.body);
    }
    return err(decode_error_body(resp.status, to_str(resp.body), ""));
}

// Raw RFC 5322 source of one message. The endpoint answers with a
// 15-minute download link which httpc follows for you.
pub fn get_received_raw(c: Client, id: str, deadline: until)
        -> result[bytes, ApiError] {
    return do_bytes(c, "GET", "/v1/received/" + id + "/raw", deadline);
}

// Answer a received message. `from` defaults to the address it was
// sent to, on its verified domain; `reply_all` answers everyone.
pub fn reply_to_received_email(c: Client, id: str, from: opt[str],
                               text: opt[str], html: opt[str],
                               subject: opt[str], reply_all: opt[bool],
                               idempotency_key: opt[str], deadline: until)
        -> result[Email, ApiError] {
    let rr = do_json(c, "POST", "/v1/received/" + id + "/reply",
                     some(json.encode(ReplyRequest {
                         from: from, text: text, html: html,
                         subject: subject, reply_all: reply_all,
                         idempotency_key: idempotency_key
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[Email, str] = json.decode(raw.body);
    guard let m = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(m);
}

// List inbound routing rules.
pub fn list_inbound_routes(c: Client, deadline: until)
        -> result[[InboundRoute], ApiError] {
    let rr = do_json(c, "GET", "/v1/inbound-routes", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[RouteList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Create a routing rule. `match_type` is exact, prefix, or catch_all;
// action is webhook, forward, or drop.
pub fn create_inbound_route(c: Client, domain_id: opt[str], match_type: str,
                            match_value: opt[str], action: opt[str],
                            endpoint_ids: opt[[str]], forward_to: [str],
                            allow_senders: [str], block_senders: [str],
                            enabled: opt[bool], deadline: until)
        -> result[InboundRoute, ApiError] {
    let rr = do_json(c, "POST", "/v1/inbound-routes",
                     some(json.encode(RouteRequest {
                         domain_id: domain_id, match_type: match_type,
                         match_value: match_value, action: action,
                         endpoint_ids: endpoint_ids, forward_to: forward_to,
                         allow_senders: allow_senders,
                         block_senders: block_senders, enabled: enabled
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_route(raw.body);
}

// Patch a routing rule. Only the given fields change.
pub fn update_inbound_route(c: Client, id: str, action: opt[str],
                            endpoint_ids: opt[[str]], forward_to: [str],
                            allow_senders: [str], block_senders: [str],
                            enabled: opt[bool], deadline: until)
        -> result[InboundRoute, ApiError] {
    let rr = do_json(c, "PATCH", "/v1/inbound-routes/" + id,
                     some(json.encode(RoutePatch {
                         action: action, endpoint_ids: endpoint_ids,
                         forward_to: forward_to, allow_senders: allow_senders,
                         block_senders: block_senders, enabled: enabled
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_route(raw.body);
}

// Delete a routing rule. Returns true when the server confirms.
pub fn delete_inbound_route(c: Client, id: str, deadline: until)
        -> result[bool, ApiError] {
    let rr = do_json(c, "DELETE", "/v1/inbound-routes/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(true);
}

// The sent+received thread around one email.
pub fn get_email_conversation(c: Client, id: str, deadline: until)
        -> result[Conversation, ApiError] {
    let rr = do_json(c, "GET", "/v1/emails/" + id + "/conversation", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[Conversation, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page);
}

gc struct QuotaAck {
    acknowledge_quota: bool
}

gc struct TestSend {
    to: str
}

gc struct ReplyRequest {
    from: opt[str],
    text: opt[str],
    html: opt[str],
    subject: opt[str],
    reply_all: opt[bool],
    idempotency_key: opt[str]
}

gc struct RouteRequest {
    domain_id: opt[str],
    match_type: str,
    match_value: opt[str],
    action: opt[str],
    endpoint_ids: opt[[str]],
    forward_to: [str],
    allow_senders: [str],
    block_senders: [str],
    enabled: opt[bool]
}

gc struct RoutePatch {
    action: opt[str],
    endpoint_ids: opt[[str]],
    forward_to: [str],
    allow_senders: [str],
    block_senders: [str],
    enabled: opt[bool]
}

fn decode_domain_receiving(body: str) -> result[DomainReceiving, ApiError] {
    let r: result[DomainReceiving, str] = json.decode(body);
    guard let d = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(d);
}

fn decode_route(body: str) -> result[InboundRoute, ApiError] {
    let r: result[InboundRoute, str] = json.decode(body);
    guard let t = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(t);
}

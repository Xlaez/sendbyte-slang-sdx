// Sending domains: registration, DNS records, verification, tracking.
//
// A domain must be verified (SPF + DKIM + DMARC) before live keys may
// send from it. Register, publish the returned records, then verify.

import "json";

// One DNS record to publish for verification.
pub gc struct DnsRecord {
    type: str,
    host: str,
    name: str,
    value: str,
    purpose: str,
    required: bool
}

pub gc struct DomainTracking {
    enabled: bool,
    host: opt[str],
    status: str
}

pub gc struct Domain {
    id: str,
    domain: str,
    status: str,
    dkim_selector: str,
    dns_records: [DnsRecord],
    verified_at: opt[str],
    deliverability_ready: bool,
    tracking: opt[DomainTracking],
    created_at: str
}

// POST /v1/domains/{id}/verify result. `checks` is intentionally not
// modeled (free-form objects); status + deliverability carry the verdict.
pub gc struct DomainVerification {
    id: str,
    domain: str,
    status: str,
    deliverability_ready: bool
}

// Register a sending domain. Returns the DNS records to publish.
pub fn create_domain(c: Client, domain: str, deadline: until)
        -> result[Domain, ApiError] {
    let rr = do_json(c, "POST", "/v1/domains",
                     some(json.encode(NewDomain { domain: domain })),
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain(raw.body);
}

// List all domains on the account.
pub fn list_domains(c: Client, deadline: until)
        -> result[[Domain], ApiError] {
    let rr = do_json(c, "GET", "/v1/domains", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain_list(raw.body);
}

// Fetch one domain with its verification status.
pub fn get_domain(c: Client, id: str, deadline: until)
        -> result[Domain, ApiError] {
    let rr = do_json(c, "GET", "/v1/domains/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain(raw.body);
}

// Delete a domain. Returns true when the server confirms.
pub fn delete_domain(c: Client, id: str, deadline: until)
        -> result[bool, ApiError] {
    let rr = do_json(c, "DELETE", "/v1/domains/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(true);
}

// Trigger a live DNS check. When every required record passes, the
// domain flips to verified immediately.
pub fn verify_domain(c: Client, id: str, deadline: until)
        -> result[DomainVerification, ApiError] {
    let rr = do_json(c, "POST", "/v1/domains/" + id + "/verify", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[DomainVerification, str] = json.decode(raw.body);
    guard let v = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(v);
}

// True when the domain may carry live traffic.
pub fn is_verified(d: Domain) -> bool {
    return d.status == "verified";
}

// Turn open/click tracking on or off for one domain. Returns the
// updated domain.
pub fn set_domain_tracking(c: Client, id: str, enabled: bool,
                           deadline: until) -> result[Domain, ApiError] {
    let rr = do_json(c, "POST", "/v1/domains/" + id + "/tracking",
                     some(json.encode(TrackingToggle { enabled: enabled })),
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_domain(raw.body);
}

gc struct NewDomain {
    domain: str
}

gc struct TrackingToggle {
    enabled: bool
}

gc struct DomainList {
    data: [Domain]
}

fn decode_domain(body: str) -> result[Domain, ApiError] {
    let r: result[Domain, str] = json.decode(body);
    guard let d = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(d);
}

fn decode_domain_list(body: str) -> result[[Domain], ApiError] {
    let r: result[DomainList, str] = json.decode(body);
    guard let page = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(page.data);
}

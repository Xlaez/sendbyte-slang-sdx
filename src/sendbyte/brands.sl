// Marketing: brands, subscriber lists, subscribers, and imports.
//
// Brands scope signup pages, footers, and campaigns. Lists hold
// subscribers with per-list status; adding someone who opted out or
// bounced elsewhere deliberately changes nothing (see skipped_reason).

import "json";

// A sending brand: what subscribers see on pages and in footers.
pub gc struct Brand {
    id: str,
    name: str,
    public_name: str,
    logo_url: opt[str],
    from_address: opt[str],
    postal_address: opt[str],
    timezone: str,
    created_at: str
}

// Membership counts by status. `subscribed` is who a campaign reaches.
pub gc struct ListCounts {
    subscribed: int,
    unconfirmed: int,
    unsubscribed: int,
    bounced: int,
    complained: int
}

pub gc struct SubscriberList {
    id: str,
    name: str,
    opt_in: str,
    counts: ListCounts,
    created_at: str
}

// One member of a list. Status is per-list: the same person may differ
// on another list.
//
// NOTE: the wire `attributes` object is deliberately not decoded: its
// values are free-form (strings, numbers, booleans) and no single
// struct shape covers them, so decoding them could fail a whole list
// on one row. Attribute *writes* take string values (see
// SubscriberInput); stringify numbers first.
pub gc struct Subscriber {
    id: str,
    email: str,
    name: opt[str],
    status: str,
    source: str,
    created_at: str
}

// What adding one subscriber reported. `skipped_reason` is set exactly
// when nothing changed (opt-out, bounce, duplicate): adding someone
// again never undoes an opt-out or a bounce.
pub gc struct AddSubscriberResult {
    id: str,
    email: str,
    status: str,
    skipped_reason: opt[str]
}

// Bulk import outcome.
pub gc struct ImportSummary {
    imported: int,
    updated: int,
    invalid: int,
    skipped: int,
    overCap: int,
    cap: opt[int],
    rejected: [RejectedRow]
}

// One row the import refused, with the reason.
pub gc struct RejectedRow {
    email: str,
    reason: str
}

pub gc struct BrandList {
    data: [Brand]
}

pub gc struct SubscriberListList {
    data: [SubscriberList]
}

pub gc struct SubscriberPage {
    data: [Subscriber]
}

// List all brands.
pub fn list_brands(c: Client, deadline: until)
        -> result[[Brand], ApiError] {
    let rr = do_json(c, "GET", "/v1/brands", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[BrandList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Create a brand. Only `name` is required; postal address becomes
// mandatory before campaigns send (bulk-sender footer rules).
pub fn create_brand(c: Client, name: str, public_name: opt[str],
                    from_address: opt[str], postal_address: opt[str],
                    timezone: opt[str], deadline: until)
        -> result[Brand, ApiError] {
    let rr = do_json(c, "POST", "/v1/brands",
                     some(json.encode(BrandRequest {
                         name: name, public_name: public_name,
                         from_address: from_address,
                         postal_address: postal_address, timezone: timezone
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[Brand, str] = json.decode(raw.body);
    guard let b = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(b);
}

// Lists of one brand.
pub fn list_subscriber_lists(c: Client, brand_id: str, deadline: until)
        -> result[[SubscriberList], ApiError] {
    let rr = do_json(c, "GET", "/v1/brands/" + brand_id + "/lists", none,
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[SubscriberListList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Create a list. `opt_in` is "single" or "double" (none = server
// default double: confirmation click required before mailing).
pub fn create_subscriber_list(c: Client, brand_id: str, name: str,
                              opt_in: opt[str], deadline: until)
        -> result[SubscriberList, ApiError] {
    let rr = do_json(c, "POST", "/v1/brands/" + brand_id + "/lists",
                     some(json.encode(ListRequest {
                         name: name, opt_in: opt_in
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[SubscriberList, str] = json.decode(raw.body);
    guard let l = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(l);
}

// Members of a list. `status` narrows (subscribed, unconfirmed, ...),
// none lists everyone.
pub fn list_subscribers(c: Client, brand_id: str, list_id: str,
                        status: opt[str], deadline: until)
        -> result[[Subscriber], ApiError] {
    let q = query_of([query_opt("status", status)]);
    let rr = do_json(c, "GET", "/v1/brands/" + brand_id + "/lists/" + list_id
                     + "/subscribers" + q, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[SubscriberPage, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Add one subscriber. Custom fields go in attributes as strings
// (stringify numbers first: the wire takes string values).
pub fn add_subscriber(c: Client, brand_id: str, list_id: str, email: str,
                      name: opt[str], attributes: map[str]str,
                      deadline: until) -> result[AddSubscriberResult, ApiError] {
    let rr = do_json(c, "POST", "/v1/brands/" + brand_id + "/lists/"
                     + list_id + "/subscribers",
                     some(json.encode(SubscriberInput {
                         email: email, name: name, attributes: attributes
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[AddSubscriberResult, str] = json.decode(raw.body);
    guard let s = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(s);
}

// Bulk import up to 1000 subscribers. Inspect the summary: invalid
// addresses, skips, and over-cap drops never fail the call itself.
pub fn import_subscribers(c: Client, brand_id: str, list_id: str,
                          subs: [SubscriberInput], deadline: until)
        -> result[ImportSummary, ApiError] {
    let rr = do_json(c, "POST", "/v1/brands/" + brand_id + "/lists/"
                     + list_id + "/import",
                     some(json.encode(ImportRequest { subscribers: subs })),
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ImportSummary, str] = json.decode(raw.body);
    guard let s = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(s);
}

// One subscriber to add or import. Attributes are string-valued;
// stringify numbers before putting them in.
pub gc struct SubscriberInput {
    email: str,
    name: opt[str],
    attributes: map[str]str
}

// Blank subscriber input with empty attributes.
pub fn new_subscriber(email: str) -> SubscriberInput {
    let no_attrs: map[str]str = {};
    return SubscriberInput { email: email, name: none, attributes: no_attrs };
}

gc struct BrandRequest {
    name: str,
    public_name: opt[str],
    from_address: opt[str],
    postal_address: opt[str],
    timezone: opt[str]
}

gc struct ListRequest {
    name: str,
    opt_in: opt[str]
}

gc struct ImportRequest {
    subscribers: [SubscriberInput]
}

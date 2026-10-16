// API keys: scoped credentials for environments and use cases.
// Create with least privilege, rotate by creating then revoking.

import "json";

// A key as list/get returns it. The secret itself is only ever shown
// once, inside CreatedKey.
pub gc struct ApiKey {
    id: str,
    name: str,
    prefix: str,
    last4: opt[str],
    scope: str,
    mode: str,
    last_used_at: opt[str],
    revoked: bool,
    created_at: str
}

// Create response: the key record plus the full secret. Store `key`
// immediately; it is never shown again.
pub gc struct CreatedKey {
    id: str,
    name: str,
    prefix: str,
    last4: opt[str],
    scope: str,
    mode: str,
    last_used_at: opt[str],
    revoked: bool,
    created_at: str,
    key: str
}

pub gc struct ApiKeyList {
    data: [ApiKey]
}

// Create a key. Scope is one of send_only, read_only, full_access;
// mode is live or test. Both default server-side when omitted here.
pub fn create_key(c: Client, name: str, scope: opt[str], mode: opt[str],
                  deadline: until) -> result[CreatedKey, ApiError] {
    let rr = do_json(c, "POST", "/v1/api-keys",
                     some(json.encode(KeyRequest {
                         name: name, scope: scope, mode: mode
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[CreatedKey, str] = json.decode(raw.body);
    guard let k = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(k);
}

// List active keys.
pub fn list_keys(c: Client, deadline: until)
        -> result[[ApiKey], ApiError] {
    let rr = do_json(c, "GET", "/v1/api-keys", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ApiKeyList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Rename a key (zero-downtime rotation starts here: create the
// replacement first, then revoke the old one).
pub fn rename_key(c: Client, id: str, name: str, deadline: until)
        -> result[ApiKey, ApiError] {
    let rr = do_json(c, "PATCH", "/v1/api-keys/" + id,
                     some(json.encode(RenameRequest { name: name })),
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[ApiKey, str] = json.decode(raw.body);
    guard let k = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(k);
}

// Revoke a key. Returns true when the server confirms.
pub fn revoke_key(c: Client, id: str, deadline: until)
        -> result[bool, ApiError] {
    let rr = do_json(c, "DELETE", "/v1/api-keys/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(true);
}

gc struct KeyRequest {
    name: str,
    scope: opt[str],
    mode: opt[str]
}

gc struct RenameRequest {
    name: str
}

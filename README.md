# sendbyte for slang

A slang package for the [SendByte](https://docs.sendbyte.africa) transactional
email API: send mail, manage domains, templates, keys, webhooks,
suppressions, marketing lists, and inbound receiving — plus webhook
verification that plugs straight into [zokor](https://github.com/dolphlabs/zokor)
handlers. Every endpoint in the
[OpenAPI spec](https://docs.sendbyte.africa/api-reference/openapi.yaml) is
covered; generated types mirror it field for field.

## Install

In your `slang.project`:

```
pkg sendbyte git https://github.com/dolphlabs/sendbyte tag v0.1.0 dir src/sendbyte
```

then `slangc get`. Import it wherever you send mail:

```
import "sendbyte";
```

## Send your first email

```slang
import "sendbyte";
import "proc";

let kr = sendbyte.new_client(proc.getenv("SENDBYTE_API_KEY") ?? "");
guard let c = kr else let e = err_of(kr) {
    println("bad key: " + e);
    exit(2);
}
let req = sendbyte.new_email("You <you@yourapp.ng>",
                             sendbyte.to_one("anyone@example.ng"));
req.subject = some("My first SendByte email");
req.html = some("<p>It works.</p>");
req.idempotency_key = some("order-4421-receipt");
let er = sendbyte.send_email(c, req, sendbyte.deadline_in(30));
guard let email = er else let e = err_of(er) {
    println("send failed: " + sendbyte.error_string(e));
    exit(1);
}
println("queued: " + email.id);
```

Use `new_test_client` / `new_live_client` to reject the wrong key family
at startup instead of at 2am. A runnable version lives in
`examples/send.sl` (`SENDBYTE_API_KEY=sk_test_... slangc examples/send.sl
--run`).

## Errors

Every call returns `result[T, sendbyte.ApiError]`, mirroring the Go
SDK's typed error and the API envelope. Branch on `code`, never on
`message`:

```slang
let rr = sendbyte.send_email(c, req, sendbyte.deadline_in(30));
guard let email = rr else let e = err_of(rr) {
    if e.code == "suppressed_recipient" {
        println("skipping suppressed address");
        return;
    }
    println(sendbyte.error_string(e));
    return;
}
```

`sendbyte.is_rate_limited(e)` spots 429s; sleep past the server's
`Retry-After` and retry. Transport failures (no HTTP exchange at all)
arrive as `code: "request_failed"`, `status: 0`.

## Receiving webhooks in zokor

```slang
import "sendbyte";

fn hook(c: zokor.Ctx[App]) -> http.Response {
    let wr = sendbyte.webhook_request(APP_SENDGRID_WHSEC, c.req);
    guard let ev = wr else let e = err_of(wr) {
        // Bad signature, stale timestamp, or malformed body: all 401s.
        return zokor.text(401, e);
    }
    if ev.type == "email.delivered" {
        guard let id = ev.data.email_id else {
            return zokor.text(200, "ok");
        }
        mark_delivered(c.state.db, id);
    }
    return zokor.text(200, "ok");
}
```

`webhook_request` verifies the `sendbyte-signature` header (HMAC-SHA256
over `"<t>.<raw body>"`, 300s freshness, constant-time compare) against
the **raw** body, then decodes the event. One secret per endpoint: when
the handler moves, edit the endpoint URL instead of registering a
second one, or every signature mismatches.

## Design notes

- **Deadlines everywhere.** Every network call takes `deadline: until`;
  `sendbyte.deadline_in(seconds)` builds one. Retries (429/5xx only,
  honors Retry-After, capped exponential backoff) run inside that budget.
- **Addresses are always `[str]`**, sending and receiving — the API
  normalizes lone addresses to one-element arrays.
- **Unset optionals encode as explicit JSON `null`**, which the API reads
  as absent. (This is slang's `json.encode`, not a choice.)
- **Timestamps stay `str`** (RFC 3339); durations stay integers.
- **`variables` and subscriber `attributes` take `map[str]str`.**
  Stringify numbers first: the wire takes string values.
- **Webhook `events` unions** (`"all"` vs `["a", ...]`, including mixed
  endpoint lists) decode through a small documented normalizer; event
  `data` decodes into a wide struct of optional string fields, so ints,
  bools, and future keys never break decoding.
- **`Subscriber.attributes` and timeline `payload` objects are not
  decoded**: their values are free-form (strings, numbers, booleans) and
  decoding them could fail whole lists on a single row. Webhook events
  carry the full typed payload instead.

## API map

| Area | Functions |
| - | - |
| Client | `new_client`, `new_test_client`, `new_live_client`, `with_base_url`, `is_live_key`, `is_test_key`, `deadline_in`, `is_rate_limited`, `error_string` |
| Emails | `new_email`, `to_one`, `attachment`, `send_email`, `get_email`, `list_emails`, `export_emails`, query helpers |
| Domains | `create_domain`, `list_domains`, `get_domain`, `delete_domain`, `verify_domain`, `is_verified`, `set_domain_tracking` |
| Templates | `new_template`, `create_template`, `list_templates`, `get_template`, `update_template`, `delete_template`, `render_template`, `preview_template` |
| Keys | `create_key`, `list_keys`, `rename_key`, `revoke_key` |
| Webhooks | `create_webhook`, `list_webhooks`, `update_webhook`, `delete_webhook`, `disable_webhook`, `enable_webhook`, `rotate_webhook_secret`, `list_webhook_deliveries`, `replay_webhook_delivery`, `verify_signature`, `decode_event`, `webhook_request`, `all_events`, `some_events`, `parse_event_filter` |
| Suppressions | `list_suppressions`, `get_suppression`, `request_suppression_removal`, `list_suppression_removals`, `get_suppression_removal`, `cancel_suppression_removal`, `resend_suppression_removal` |
| Brands/lists | `list_brands`, `create_brand`, `list_subscriber_lists`, `create_subscriber_list`, `list_subscribers`, `add_subscriber`, `import_subscribers`, `new_subscriber` |
| Receiving | `get_receiving`, `enable_receiving`, `disable_receiving`, `send_receiving_test`, `enable_domain_receiving`, `disable_domain_receiving`, `check_domain_receiving`, `preflight_domain_receiving`, `list_received_emails`, `received_email_stats`, `get_received_email`, `get_received_attachment`, `download_attachment`, `get_received_raw`, `reply_to_received_email`, `list_inbound_routes`, `create_inbound_route`, `update_inbound_route`, `delete_inbound_route`, `get_email_conversation` |

## Developing

`slangc test src/sendbyte` runs the offline unit tests (no network, no
keys). Live calls need a real key; the sandbox (`sk_test_…`) simulates
delivery end to end — try `examples/send.sl` with one.

// Reusable server-side templates (Handlebars or MJML): create, send
// with variables, preview, and render without sending.

import "json";

// A template as the API returns it.
pub gc struct Template {
    id: str,
    name: str,
    subject: str,
    version: int,
    format: str,
    html: opt[str],
    text: opt[str],
    mjml: opt[str],
    created_at: str,
    updated_at: str
}

// Fields to create a template. Give at least one of html, text, mjml.
pub gc struct TemplateInput {
    name: str,
    subject: str,
    html: opt[str],
    text: opt[str],
    mjml: opt[str]
}

// A render/preview result: the template with variables applied.
pub gc struct RenderedTemplate {
    subject: str,
    html: opt[str],
    text: opt[str]
}

pub gc struct TemplateList {
    data: [Template]
}

// Blank template input: fill name, subject, and one body format.
pub fn new_template(name: str, subject: str) -> TemplateInput {
    return TemplateInput { name: name, subject: subject, html: none,
                           text: none, mjml: none };
}

// Create a template. Names match ^[a-zA-Z0-9-_]+$ on the server.
pub fn create_template(c: Client, input: TemplateInput, deadline: until)
        -> result[Template, ApiError] {
    let rr = do_json(c, "POST", "/v1/templates", some(json.encode(input)),
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_template(raw.body);
}

// List all templates.
pub fn list_templates(c: Client, deadline: until)
        -> result[[Template], ApiError] {
    let rr = do_json(c, "GET", "/v1/templates", none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[TemplateList, str] = json.decode(raw.body);
    guard let page = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(page.data);
}

// Fetch one template by id or name.
pub fn get_template(c: Client, id: str, deadline: until)
        -> result[Template, ApiError] {
    let rr = do_json(c, "GET", "/v1/templates/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_template(raw.body);
}

// Replace a template wholesale (same shape as create).
pub fn update_template(c: Client, id: str, input: TemplateInput,
                       deadline: until) -> result[Template, ApiError] {
    let rr = do_json(c, "PUT", "/v1/templates/" + id,
                     some(json.encode(input)), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return decode_template(raw.body);
}

// Delete a template. Returns true when the server confirms.
pub fn delete_template(c: Client, id: str, deadline: until)
        -> result[bool, ApiError] {
    let rr = do_json(c, "DELETE", "/v1/templates/" + id, none, deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(true);
}

// Render ad-hoc content with variables, without creating or sending
// anything. Any of html/text/mjml may be set; variables default to {}.
pub fn render_template(c: Client, subject: str, html: opt[str],
                       text: opt[str], mjml: opt[str],
                       variables: map[str]str, deadline: until)
        -> result[RenderedTemplate, ApiError] {
    let rr = do_json(c, "POST", "/v1/templates/render",
                     some(json.encode(RenderRequest {
                         subject: subject, html: html, text: text, mjml: mjml,
                         variables: variables
                     })), deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[RenderedTemplate, str] = json.decode(raw.body);
    guard let out = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(out);
}

// Preview a stored template with variables, without sending.
pub fn preview_template(c: Client, id: str, variables: map[str]str,
                        deadline: until) -> result[RenderedTemplate, ApiError] {
    let rr = do_json(c, "POST", "/v1/templates/" + id + "/preview",
                     some(json.encode(PreviewRequest { variables: variables })),
                     deadline);
    guard let raw = rr else let e = err_of(rr) {
        return err(e);
    }
    let r: result[RenderedTemplate, str] = json.decode(raw.body);
    guard let out = r else let e = err_of(r) {
        return err(decode_error_body(raw.status, e, raw.request_id));
    }
    return ok(out);
}

gc struct RenderRequest {
    subject: str,
    html: opt[str],
    text: opt[str],
    mjml: opt[str],
    variables: map[str]str
}

gc struct PreviewRequest {
    variables: map[str]str
}

fn decode_template(body: str) -> result[Template, ApiError] {
    let r: result[Template, str] = json.decode(body);
    guard let t = r else let e = err_of(r) {
        return err(ApiError { code: "decode_error", message: e, docs_url: "",
                              status: 200, request_id: "" });
    }
    return ok(t);
}

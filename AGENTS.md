# AGENTS.md — sendbyte (slang package)

A slang package for the SendByte transactional email API
(https://docs.sendbyte.africa), built against
https://docs.sendbyte.africa/api-reference/openapi.yaml.

## Commands

- `slangc test src/sendbyte` — offline unit tests (no network, no keys).
- `slangc <file> --run` — compile and run (examples need `SENDBYTE_API_KEY`).
- New code must compile warning-free and keep `slangc test` green.

## Conventions (slang-specific, easy to get wrong)

- **No trailing commas** anywhere: not in struct literals, lists, calls,
  or declarations. The compiler rejects them.
- **`err_of(x)` takes the let-bound variable**, never a call: bind first
  (`let rr = f(...); guard let v = rr else let e = err_of(rr)`), or the
  call runs twice / fails to compile.
- **`str` cannot be indexed or sliced** — work on `bytes` (`to_bytes`,
  integer indexing) and convert back with `to_str`.
- **`json.encode` emits explicit `null` for `none` fields**; the API reads
  nulls as absent. Do not hand-build JSON to dodge this.
- **`json.decode` is strict and typed**: missing non-`opt` keys and
  wrong-shape values are errors; unknown keys are ignored. Prefer `opt`
  for nullable/conditional fields, and omit free-form objects (`map`
  with mixed values cannot decode — see `normalize_events` and the
  `EventData` wide-struct pattern in webhooks.sl).
- Every network call takes `deadline: until` and returns
  `result[T, ApiError]`; branch errors on `e.code`, never `e.message`.
- Test files live beside sources as `*_test.sl` with `fn test_*()` using
  `assert(cond, msg)`. Tests must run offline: fixed fixtures, hand-built
  signatures, round-trips — never network or keys.

## API fidelity

- Field names must match the OpenAPI wire names verbatim (notably
  camelCase like `overCap`); `json.decode` maps keys verbatim.
- Response shapes: lists arrive as `{data: [...]}` envelopes; check the
  spec per endpoint rather than assuming, especially for new endpoints.
- When the spec is ambiguous, mirror the official Go SDK
  (`github.com/Sendbyte-Africa/sendbyte-go`) and note the decision.

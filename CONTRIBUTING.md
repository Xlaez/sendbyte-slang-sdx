# Contributing to sendbyte-slang-sdx

Thank you for wanting to help. This file is what you need to build the
package, run its tests, and get a change merged.

By contributing you agree that your contribution is licensed under the
[MIT licence](LICENSE), like the rest of the project. Please sign your commits
off (`git commit -s`), which adds a `Signed-off-by:` line certifying the
[Developer Certificate of Origin](https://developercertificate.org/).

Everyone taking part is expected to follow the [Code of
Conduct](CODE_OF_CONDUCT.md). To report a security problem, read
[SECURITY.md](SECURITY.md) and do not open a public issue.

## Build and test

You need the slang toolchain (`slangc`; see
[slang](https://github.com/dolphlabs/slang)):

```sh
slangc test src/sendbyte   # the whole suite, offline: no network, no keys
```

Tests live beside sources as `*_test.sl` with `fn test_*()` using
`assert(cond, msg)`. Every test must run offline with fixed fixtures —
never network calls or API keys. A live sandbox check is manual:
`SENDBYTE_API_KEY=sk_test_... slangc examples/send.sl --run`.

## What a change needs

- **A test.** Unit tests for new functions; regression tests with the exact
  failing payload for fixes. A test that passes on broken code proves nothing —
  show it failing first where you can.
- **API fidelity.** Field names must match the SendByte wire names verbatim
  (check the [OpenAPI spec](https://docs.sendbyte.africa/api-reference/openapi.yaml),
  not your intuition). When the spec is ambiguous, mirror the official Go SDK
  (`github.com/Sendbyte-Africa/sendbyte-go`) and say so in the PR.
- **No network in tests.** If you need a new live behavior, cover the pure
  parts (builders, decoders, verifiers) offline and exercise the wire
  manually with a sandbox key.
- **Docs.** Update `README.md` (API map, design notes) when behavior a user
  can see changes. Keep the `CHANGE LOG` section in the README current.

## Workflow

- `main` is the release branch. Branch each change from an up-to-date `main`,
  one branch per task, and open the pull request against `main`.
- **Commits:** conventional commits (`feat(emails): …`, `fix(webhooks): …`),
  subject ≤ 72 characters, imperative mood, with a body saying what and why.
- Write the pull request description for someone who has not seen the
  conversation: what changed and why, the evidence (what failed before, what
  passes now), and anything you did not do.

## Releasing

Tag `main` with a version tag; each tag should correspond to a tested state:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Consumers pin it from their `slang.project`:

```
pkg sendbyte git https://github.com/Xlaez/sendbyte-slang-sdx tag v0.1.0 dir src/sendbyte
```

then `slangc get`.

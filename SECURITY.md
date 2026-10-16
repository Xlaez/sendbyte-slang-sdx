# Security policy

## Supported versions

Only the latest release (see [releases](https://github.com/Xlaez/sendbyte-slang-sdx/releases))
and `main` get security fixes.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.** Report it
privately through GitHub:

<https://github.com/Xlaez/sendbyte-slang-sdx/security/advisories/new>

(or the repository's **Security** tab → **Report a vulnerability**). Only the
maintainers can see it.

If that form is not available, open a public issue titled
`security contact request` with **no details** in it, and a maintainer will
arrange a private way to talk.

A useful report has:

- the package version (release tag or commit) and the `slangc` version;
- the smallest program, request bytes, or webhook payload that shows it;
- what you expected, what happened, and what you think an attacker gains.

We will acknowledge the report, keep you informed while we work on it, and
credit you in the fix unless you would rather we did not. Please give us a
reasonable chance to fix a problem before you publish it.

## What counts as a vulnerability

In scope:

- **Webhook signature bypass**: anything that lets a forged delivery pass
  `verify_signature` / `webhook_request`, including timing side channels
  in the comparison or timestamp handling that admits replays.
- **Credential exposure**: the SDK logging, persisting, or otherwise
  leaking API keys or webhook secrets (error strings, debug output).
- **Response handling that trusts the network**: crashes or hangs on
  malformed API responses (every decode failure must surface as
  `ApiError`, never a panic), and retry behavior that amplifies an
  outage (unbounded retries, ignoring Retry-After).

Not in scope:

- Bugs in a user's own program logic.
- Problems in the slang toolchain, its standard library, or OpenSSL
  themselves; report those to [dolphlabs/slang](https://github.com/dolphlabs/slang)
  or upstream. This package vendors none of them (see
  [THIRD_PARTY.md](THIRD_PARTY.md)).
- The SendByte API or dashboard themselves; report those to SendByte
  support.

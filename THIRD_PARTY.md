# Third-party software

This package itself is MIT-licensed (see [LICENSE](LICENSE)). This file says
what it touches that is not, and what that means for you.

**This repository contains no third-party source code.** There are no vendored
libraries.

## Build-time and runtime surroundings

The package is written in [slang](https://github.com/dolphlabs/slang) (MIT)
and uses only its standard library (`httpc`, `json`, `time`, `crypto`,
`encoding`, `strings`, `builder`, `http`) plus the language itself. Those
ship with the slang toolchain, not with this repository; their licences
ride with your slang installation.

It speaks to the [SendByte API](https://docs.sendbyte.africa) over HTTPS.
The API's terms of service govern that traffic. Design references were
drawn from SendByte's [OpenAPI spec](https://docs.sendbyte.africa/api-reference/openapi.yaml)
and its official Go SDK (`github.com/Sendbyte-Africa/sendbyte-go`); no code
was copied from either.

## Things this repository refers to but does not ship

- **The Contributor Covenant**, version 2.1, in
  [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), is used under its Creative Commons
  Attribution 4.0 licence; the attribution is in that file.

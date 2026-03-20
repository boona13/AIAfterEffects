# Security Policy

## Supported Status

This project is currently in a **pre-release** state. Security fixes will be handled on a best-effort basis while the app is still stabilizing.

## Reporting A Vulnerability

Please do **not** open a public issue for:

- leaked credentials
- hardcoded secrets
- auth or token-handling problems
- local file exposure
- prompt or tool execution paths that could expose sensitive data

Instead, report the issue privately to the maintainer through a non-public channel you trust.

## Secret Handling Expectations

- no hardcoded production API keys in the repository
- user-provided credentials should stay local to the machine
- local debug request/response captures must not be committed

If you discover a secret that may already be exposed, assume it is compromised and rotate it immediately.

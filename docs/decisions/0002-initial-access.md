# 0002. Initial access and sessions

Status: Accepted for the initial account flow on 2026-10-02.

## Context

Bolognesa needs a real administrator before libraries can be configured. The initial deployment has no mail service or password-recovery flow and is intended for private HTTP access on a trusted network.

## Decision

- Keep `/setup` open only until the first administrator is created. A database constraint prevents simultaneous setup requests from creating multiple administrators.
- Normalize a unique ASCII email and store only a bcrypt password hash. Never commit credentials.
- Give each browser a distinct random token; store only its SHA-256 hash. Sessions expire 30 days after creation without sliding renewal. Signing out revokes the current token.
- Resolve a verified actor for protected routes and LiveViews. Backend use cases enforce their own authorization.
- Require HTTPS before enabling public or remote access. The current private HTTP profile cannot protect credentials from someone who can observe local network traffic.

## Consequences

There is a setup window before the first account is created, so initial setup should be completed promptly after installation. There is no password recovery in this flow; losing the password can lock out the operator. The HTTP deployment is limited to a trusted private network.

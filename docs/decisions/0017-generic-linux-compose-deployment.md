# 0017. Generic Linux Docker Compose deployment

Status: Implemented and deployed through the shared deployment system.

## Context

Bolognesa began on a QNAP NAS, and its deployment files made that device appear to be an application requirement. The application itself needs Linux, Docker Compose, PostgreSQL, local media mounts, and common media tools. The root Compose file is for local development, not server operation.

## Decision

- Keep root Compose for local development and use `deploy/compose/` for server deployment.
- Configure application and PostgreSQL networking, persistent storage, media roots, and resource limits. Mount media read-only and never publish PostgreSQL.
- Support bridge or host networking and volume or bind-mounted database storage when the operator's environment requires it.
- Bind the web port to loopback by default; allow explicit private-interface binding. The HTTP profile is for trusted LAN/Tailscale networks and must not be exposed directly to the Internet.
- Publish multi-architecture Linux images for AMD64 and ARM64. Pin deployments to a commit tag or immutable digest.
- Keep secrets and host-specific paths in ignored runtime configuration. Preserve existing project names and data paths during upgrades; verify backups and migrations before activation.

## Consequences

The application does not need to know the host vendor or directory layout. More deployment options require the operator to choose Compose files and data paths carefully. HTTP does not encrypt credentials or cookies. This profile must not be exposed directly to the public Internet; general remote access is outside the experimental preview, and adding TLS alone does not establish a supported public deployment. Local integration with synthetic data verifies deployment mechanics but does not establish a particular server's performance.

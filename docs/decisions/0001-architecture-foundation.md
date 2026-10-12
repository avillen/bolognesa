# 0001. Application architecture

Status: Accepted on 2026-09-29.

## Context

Bolognesa is a personal learning project intended for home use. It needs clear boundaries while keeping its first version small and easy to operate.

## Decision

- Use one Phoenix application organized into bounded contexts.
- Keep domain structs and rules independent of Ecto; use ports and adapters for persistence and integrations.
- Keep domain entities separate from Ecto schemas, with explicit mappers.
- Organize LiveViews by screen and feature. Use screen-local reducers with a `call(socket, ...)` interface and view state/forms only where needed.

## Consequences

This accepts more modules and explicit mapping in exchange for independent domain rules and clear boundaries. Reducers depend on LiveView and may perform effects; they are not pure reducers. Add abstractions when a real use case needs them. Umbrella apps and separate services were considered but would add operational work without a current need.

Current details live in [backend](../conventions/backend.md) and [frontend](../conventions/frontend.md) conventions.

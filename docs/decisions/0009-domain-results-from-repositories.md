# 0009. Domain results from repositories

Status: Accepted; the identified contracts have been adapted locally.

## Context

Some repository ports returned maps or schemas, allowing persistence details and untyped structures to leak into application code.

## Decision

Repositories return domain models for business data, never Ecto schemas, application DTOs, or free-form maps. Compound reads use typed collections or tuples and explicit scalar metadata. Operations without an entity may return explicit values such as `:ok`, booleans, IDs, counts, or named states. Input attribute maps remain valid when a port contract calls for them.

## Consequences

Persistence boundaries describe their data more clearly and do not force callers to depend on Ecto or implicit map keys. Some readers may load additional fields to construct complete domain models; consider that cost per query. See [decision 0010](0010-context-owned-models.md) for context-owned read models.

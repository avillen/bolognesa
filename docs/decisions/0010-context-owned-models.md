# 0010. Models owned by each context

Status: Accepted and implemented locally.

## Context

Catalog and Identification readers had reused entities and mappers from other contexts. Those contracts depended on modules and fields that could change for reasons unrelated to the caller.

## Decision

- Each context owns models for its reads and operations, with only the data it needs. A small amount of duplicated data is preferable to sharing entities for convenience.
- Cross-context calls go through public facades and use IDs when sufficient. Identification can write a request in the inventory transaction through an explicit facade operation.
- Shared Ecto schemas remain in `Bolognesa.Infrastructure.Persistence`. Shared physical path validation belongs to neutral infrastructure.
- `Identity.Domain.Actor` remains the explicit authenticated-identity contract for protected operations.

## Consequences

Readers return local projections and no longer reuse another context's mappers. Some fields and conversions are duplicated, while changes to one context's model no longer force unrelated contract changes. Tables, migrations, and authorization rules are unchanged.

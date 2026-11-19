# 0030. Shared identification job infrastructure

Status: Implemented locally.

## Decision

Movies and Series share the identification job mechanics that have no business rules, as [0019](0019-content-context-boundaries.md) allows. They live in `Bolognesa.Infrastructure.Jobs` and take the owner's worker, schema, content type, use case and repository as arguments:

- `IdentificationJob` inserts the token-protected Oban job in the caller's transaction and runs it, validating the arguments and reporting unexpected failures.
- `IdentificationRecovery` selects pending decisions whose job ended or stalled, filtered by library content type before the batch limit.
- `IdentificationReconciler` runs the owner's reconcile use case periodically.

## Stays in each context

Workers (queue, attempts, timeout, provider and repository wiring), reconcile and retry use cases, request writers, decision stores and identification repositories remain owner modules. Process names, the shared queue, recovery budgets, type filters and startup controls are unchanged, and neither context imports the other.

Use cases, request writers and repositories still look alike. Sharing them would need parameters for the owner's tables, policies and events, which is the central identification ownership that 0019 rejects.

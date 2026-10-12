# 0003. Durable scans with per-attempt generations

Status: Accepted; implemented. Recovery after interruption still needs verification on a real deployment.

## Context

Library scanning needs persistent inventory, work outside web requests, recovery after interruption, and protection from stale results. There is no evidence to justify higher scan concurrency.

## Decision

Use Oban with PostgreSQL behind application ports. Enqueue a scan in the same transaction as its request. The database allows one active scan per library; the initial queue concurrency is one per application instance.

Each invocation acquires a new generation. Batch writes, completion, and failure handling check that generation in the transaction that applies their effects. A retry starts the scan again and keeps already committed batches; only a complete scan can mark unseen files absent.

Identify a file by `(library_id, relative_path)`, preserving path bytes. Size and modification time define the observed revision. Renames create a new entry; content hashing and cross-library deduplication are out of scope. Partial scans preserve prior availability for unseen entries.

Reconcile persisted domain state with Oban's state after recovery. A generation check protects against duplicate or stale jobs; the system does not guarantee exactly-once execution.

## Consequences

Oban adds a dependency and tables, while avoiding a custom job engine. Lifeline recovery may cause duplicate execution, so application generations remain necessary. Queue limits are per instance, not global. Measure CPU, memory, and responsiveness before raising concurrency.

See [backend conventions](../conventions/backend.md) for current rules and [Oban documentation](https://oban.hexdocs.pm/2.19.4/Oban.html).

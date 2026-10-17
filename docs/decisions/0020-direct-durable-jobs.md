# 0020. Direct durable job creation

Status: Accepted; inspection, Music import and video identification delivery implemented locally. Verification belongs in project status.

## Decision

When business state and Oban jobs share PostgreSQL, insert the request and job in the same transaction and persist the resulting job reference before commit. A second event table and polling dispatcher add no durability to this boundary. Worker constructors own queue and retry configuration. External tools and provider calls remain outside transactions.

Libraries inventory batches now persist inspections and their Oban jobs atomically. Tokens, revisions, generations, recovery and post-persistence PubSub hints remain unchanged. Use the supported Oban insertion API (with Ecto.Multi when a supplied transaction repository is required), preserving queue insertion notifications as well as job persistence. This supersedes the inspection outbox mechanism in decision 0004.

Music now persists its pending import and linked job through its public transaction-aware facade when accepting a current successful audio inspection. Recovery reads the import request directly, including jobs that never started. Attempt token and job ownership reject obsolete work at the same revision. This supersedes event-based delivery and recovery in decision 0018.

Movies and Series now create and link their identification jobs inside their existing owner-specific request writers, covering inventory, backfill and explicit retries. This supersedes the outbox mechanism retained in decision 0019. Their independent domain models, workers, recovery, manual precedence and ordered episode associations remain intact.

Cross-context integrations use explicit transaction-aware owner facades. Each owner retains its domain rules, worker, persistence and recovery. No generic workflow engine is introduced.

## Migration and consequences

Offline migrations stop old workers, preserve matching jobs and existing data, convert current undelivered requests in batches of at most 100, and drop the replaced event table. Terminal or deleted job evidence remains available to recovery. Independently validate every eligible active request against its own job and revision before dropping events, including requests with no matching event. A Music retry may legitimately reference a different job than its original event; validate the current request rather than the old event reference. Inconsistent current requests abort the migration. No reset or required rescan is part of the upgrade.

Dropping event history is irreversible. Returning to the old application requires the matching pre-migration database backup. Large backlogs can extend the migration transaction and require a measured rehearsal. Direct insertion adds job writes to the original transaction; bounded inventory batches remain necessary.

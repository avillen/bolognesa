# 0020. Direct durable job creation

Status: Accepted; inspection delivery implemented locally. Music and video identification conversion are planned separately. Verification belongs in project status.

## Decision

When business state and Oban jobs share PostgreSQL, insert the request and job in the same transaction and persist the resulting job reference before commit. A second event table and polling dispatcher add no durability to this boundary. Worker constructors own queue and retry configuration. External tools and provider calls remain outside transactions.

Libraries inventory batches now persist inspections and their Oban jobs atomically. Tokens, revisions, generations, recovery and post-persistence PubSub hints remain unchanged. This supersedes the inspection outbox mechanism in decision 0004; the remaining Music and video outboxes retain their existing contracts until replaced independently.

Cross-context integrations use explicit transaction-aware owner facades. Each owner retains its domain rules, worker, persistence and recovery. No generic workflow engine is introduced.

## Migration and consequences

Offline migrations stop old workers, preserve matching jobs and existing data, convert current undelivered requests in batches of at most 100, and drop the replaced event table. Terminal or deleted job evidence remains available to recovery. Inconsistent current requests abort the migration. No reset or required rescan is part of the upgrade.

Dropping event history is irreversible. Returning to the old application requires the matching pre-migration database backup. Large backlogs can extend the migration transaction and require a measured rehearsal. Direct insertion adds job writes to the original transaction; bounded inventory batches remain necessary.

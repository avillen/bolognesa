# Plan 3: direct Movies and Series identification jobs

Status: proposed; implementation has not started.

**Design:** [Shared ownership, invariants, migration and verification policy](direct-jobs-design.md). Read it first.

**Starting point:** Plans 1 and 2 are complete. They are independently releasable; this plan needs no transitional adapters from either.

**Execution:** Implement sequentially using the executing-plans workflow. Movies and Series have separate implementation tasks, then one release migration and integrated review. Do not deploy intermediate task commits.

## Scope and contracts

Preserve each facade's existing `request_batch_in_transaction!(repo, entries) :: non_neg_integer()` contract, where each entry contains `file_id`, `revision`, and `requested?`. Preserve existing wrong-type behavior, manual precedence and request generation semantics. Retain independent domain models, persistence, workers, providers, and recovery; introduce no generic identification engine.

Each owner's EctoRequestWriter saves its pending decision, constructs its own IdentificationWorker with `%{file_id: file_id, token: token}`, inserts the Oban job in the same transaction, and links `job_id` to the current decision before commit. Use the supplied repo consistently. Require an active transaction for the transaction-aware entry point. Use worker-defined queue/attempt settings; keep both workers in the existing `identifications` queue with the current concurrency budget.

Keep existing payloads and worker names so queued jobs remain executable. Provider calls stay outside transactions. Beginning/completing work still revalidates current token, revision, availability and owner type. Preserve manual choices and atomic work/association persistence. Tokens distinguish requests; do not make job ID mandatory for public test/integration paths that currently permit nil without reviewing those contracts.

Scan handoff, backfill and explicit retry must all use the owner's request writer. Backfill opens its own transaction; retry and scan already have transaction boundaries. Inspect and preserve the common file → owner decision lock order across these callers. An error inserting or linking a job must roll back every enclosing change, including inventory, inspections, associations and scan progress.

## Task 1: Movies request creation

**Modify:**
- `lib/bolognesa/movies/infrastructure/repositories/ecto_request_writer.ex`
- `lib/bolognesa/movies/infrastructure/repositories/ecto_identification_repository.ex` if transaction/retry handling requires adjustment.
- `test/bolognesa/movies/identification_outbox_test.exs` → retain behavioral tests in `identification_jobs_test.exs`.
- `test/bolognesa/movies/request_backfill_test.exs`
- `test/bolognesa/movies/identification_storage_test.exs`
- `test/bolognesa/movies/identification_recovery_test.exs`
- `test/bolognesa/movies/ownership_test.exs`
- `test/bolognesa/libraries/scan_inventory_test.exs`

- [ ] Update request tests to assert a pending decision with a matching linked Oban job immediately after commit. Cover scan, backfill and explicit retry, plus rejection outside a transaction.
- [ ] Preserve manual-origin rejection, wrong-type protection, unchanged scan behavior and type filtering before backfill limits. Repeated scans must not introduce extra work; explicit new requests retain their existing fresh-token semantics.
- [ ] Replace movie-event failure injection with a PostgreSQL rejection of job insertion and separately job linking. Assert full inventory/request/inspection/counter rollback, with no orphan job. Keep Series event rollback tests intact until Task 2.
- [ ] Run changed tests to observe the expected failure. Replace insert_event! with the owner's worker construction, transactional Oban insertion and decision job link. Keep event infrastructure only until migration, with no new runtime event writes.
- [ ] Verify discarded, cancelled, completed and deleted jobs still recover pending decisions without needing event rows. Waiting retries and unexpired execution must not starve recovery limits.
- [ ] Run `mix test test/bolognesa/movies test/bolognesa/libraries/scan_inventory_test.exs`.

## Task 2: Series request creation

**Modify:**
- `lib/bolognesa/series/infrastructure/repositories/ecto_request_writer.ex`
- `lib/bolognesa/series/infrastructure/repositories/ecto_identification_repository.ex` if needed for retry transactions.
- `test/bolognesa/series/identification_outbox_test.exs` → `identification_jobs_test.exs`.
- `test/bolognesa/series/request_backfill_test.exs`
- `test/bolognesa/series/identification_storage_test.exs`
- `test/bolognesa/series/identification_recovery_test.exs`
- `test/bolognesa/series/ownership_test.exs`
- `test/bolognesa/series/episode_selection_test.exs`
- `test/bolognesa/libraries/scan_inventory_test.exs`

- [ ] Assert immediate pending decision/job linkage for scan, backfill and retry, and no mutation for movie/music files or calls outside a transaction.
- [ ] Replace the Series event failure injection with rejected job insertion/linking. Assert inventory, inspection, decision, ordered episode association changes and scan counter all roll back.
- [ ] Implement direct job creation inside the existing writer transaction. Keep EntryStore.replace! atomic with the decision and job. Preserve manual episode choices, same-season and maximum-selection rules.
- [ ] Exercise stale token/revision results, manual correction racing automatic work, duplicate jobs and interruption recovery using current regressions. Fill uncovered Series manual-race scenarios without weakening Movies coverage.
- [ ] Verify bounded backfill/recovery filters by Series type before the batch limit. Assert the two owners cannot consume or mutate one another's requests despite sharing a queue.
- [ ] Run `mix test test/bolognesa/series test/bolognesa/libraries/scan_inventory_test.exs`.

## Task 3: Migrate pending video requests and remove dispatchers

**Create:**
- `priv/repo/migrations/<timestamp>_replace_video_identification_outboxes_with_jobs.exs`
- `scripts/verify_video_jobs_migration.exs`

**Remove:**
- `lib/bolognesa/movies/infrastructure/repositories/ecto_outbox_repository.ex`
- `lib/bolognesa/series/infrastructure/repositories/ecto_outbox_repository.ex`
- `lib/bolognesa/movies/infrastructure/jobs/outbox_dispatcher.ex`
- `lib/bolognesa/series/infrastructure/jobs/outbox_dispatcher.ex`
- `lib/bolognesa/infrastructure/persistence/movie_identification_event_schema.ex`
- `lib/bolognesa/infrastructure/persistence/series_identification_event_schema.ex`

**Modify:** `lib/bolognesa/application.ex`, `config/config.exs`, `config/test.exs`, `config/screenshots.exs`, affected fixtures and scripts. Keep both identification reconcilers.

- [ ] Seed both owners with undelivered requests, healthy linked jobs, terminal/deleted linked jobs, obsolete events, manually corrected decisions, missing files and mismatched owner types. Capture movie/series/season/episode IDs and ordered association snapshots.
- [ ] In migration-local keyset batches, preserve matching jobs and link existing matching worker/file/token jobs before considering insertion. Materialize jobs only for current eligible undelivered pending decisions. Preserve terminal/missing linked evidence for existing recovery; do not retry failed/unmatched/manual decisions or recreate cleared associations.
- [ ] Validate ownership, token and revision before converting each current request. Abort unexplained inconsistencies. Drop `movie_identification_events` and `series_identification_events` after successful conversion. Explicitly refuse down and document backup restoration.
- [ ] Remove identification_outbox_dispatcher flags, dispatcher supervision and runtime references. Update startup expectations to the actual remaining processes, without combining reconcilers.
- [ ] Verify empty and seeded upgrades, full fresh migration chain, and cumulative upgrade from the original schema through all three plans. Run new workers/recovery on migrated requests and compare stable data/association snapshots.
- [ ] Preserve historical migrations/verifiers: inspect their assumptions and adapt only current fixture/bootstrap helpers required by the new schema. Do not rewrite historical migration behavior.

## Task 4: Integrated verification and decision update

- [ ] Run `mix test test/bolognesa/movies test/bolognesa/series test/bolognesa/libraries test/bolognesa/playback` and all three new migration verifiers against disposable databases.
- [ ] Run `mix precommit`. Review rollback boundaries, stale/manual races, owner separation, recovery limits, nil job-ID contracts, private SQL/job errors and provider calls outside transactions.
- [ ] Update the shared direct-job decision, decision 0019's retained-outbox conclusion, decision index, backend convention, deployment guide and status. Clearly mark only superseded mechanisms; preserve unrelated accepted ownership rules.
- [ ] Confirm no production event writers/readers/dispatchers remain for these pipelines. PubSub hints, correction UI, catalog queries and typed Playback contracts must remain intact.

## Acceptance

Both owners commit pending requests and matching jobs atomically from every entry point. Wrong-type requests cannot mutate another owner's state. Manual choices and ordered episode associations survive concurrent work and upgrade. Existing pending jobs remain executable and recoverable. The two video outbox tables and dispatchers are removed. All focused checks, migration verifiers and precommit pass, with local evidence recorded separately from deployment.

## Review focus

1. Manual correction between request and provider response: current manual state wins.
2. Failed job linking after association replacement: the complete enclosing transaction rolls back.
3. Mixed-type backlog larger than 100: each owner applies its eligibility filter before limiting.
4. Old pending job after revision/token change: harmless stale outcome without association changes.
5. Upgrade with terminal jobs and confirmed manual decisions: preserve failure evidence and user choices without implicit retry.

# Plan 1: direct inspection jobs in Libraries

Status: implemented locally; verification recorded in project status. Not deployed.

**Design:** [Shared ownership, invariants, migration and verification policy](direct-jobs-design.md). Read it before this plan.

**Execution:** sequential implementation with the executing-plans workflow. This plan ends in a releasable change. No deployment is authorized by this document.

## Scope

All library content types. Music refresh and video identification outboxes remain operational and unchanged in this release. Keep existing public interfaces and inspection payloads.

## Request contract


`EctoScanRepository.save_batch/3` continues to own the inventory transaction. When an inspection is requested:

1. Save/reset its current state with a fresh token and current revision.
2. Insert `InspectionWorker.new(%{media_file_id: file.id, token: token})` with Oban inside that transaction.
3. Persist the resulting `job_id` on the inspection before commit.

Use InspectionWorker's queue and attempt configuration instead of duplicating string constants or `max_attempts: 3`. A job insertion or link failure aborts inventory, inspection, counter, and downstream writes together. No worker or filesystem operation executes inside the transaction.

Retain a private request helper in EctoScanRepository initially. Introduce no new port for this adapter-local transaction mechanism.

## Task 1: Create inspection jobs in the inventory transaction

**Modify:**
- `lib/bolognesa/libraries/infrastructure/repositories/ecto_scan_repository.ex`
- `test/bolognesa/libraries/scan_inventory_test.exs`
- `test/bolognesa/libraries/inspection_pipeline_test.exs`
- Relevant fixtures in `test/support/` that assume an event is required to schedule inspection.

**Deliverable:** Every new inspection request commits with a valid job ID; existing generation/revision behavior is unchanged.

- [x] Read the inventory/outbox/pipeline tests and identify assertions that protect behavior versus event-table implementation.
- [x] Update inventory and pipeline assertions to require the committed inspection and matching Oban job directly, with the worker's queue and retry budget.
- [x] Replace the event-insertion failure regression with an injected PostgreSQL rejection of inspection job insertion; assert inventory, inspection, scan counter, video request, and owner event rollback together. Use disposable transaction-local constraints and guaranteed cleanup as in existing tests.
- [x] Cover unchanged scans, forced inspection once per generation, restored/changed files, stale jobs, and concurrent duplicate batches using existing regressions.
- [x] Run the changed tests to establish the expected failure, then replace event insertion with Worker.new → Oban.insert → inspection job link inside the inventory transaction.
- [x] Keep legacy inspection event infrastructure only until this plan's migration task has preserved existing requests. Intermediate task commits are not releases.
- [x] Run `mix test test/bolognesa/libraries/scan_inventory_test.exs test/bolognesa/libraries/inspection_pipeline_test.exs test/bolognesa/libraries/inspection_recovery_test.exs`.

## Task 2: Upgrade existing inspection requests and remove the outbox

**Create:** `priv/repo/migrations/<timestamp>_replace_inspection_outbox_with_jobs.exs` and `scripts/verify_inspection_jobs_migration.exs`.

**Remove:**
- `lib/bolognesa/libraries/application/ports/repositories/outbox_repository.ex`
- `lib/bolognesa/libraries/infrastructure/repositories/ecto_outbox_repository.ex`
- `lib/bolognesa/libraries/infrastructure/jobs/outbox_dispatcher.ex`
- `lib/bolognesa/infrastructure/persistence/inspection_event_schema.ex`

**Modify:** `lib/bolognesa/application.ex`, `config/config.exs`, `config/test.exs`, `config/screenshots.exs`, `test/bolognesa/libraries/inspection_outbox_test.exs`, affected fixtures/scripts.

- [x] Seed pending undelivered, linked waiting/running, discarded/cancelled/completed/deleted jobs, obsolete tokens, changed revisions, missing files and successful/failed inspections in a disposable database.
- [x] Migrate only current inspection requests. Preserve matching linked jobs. Insert/link jobs for current undelivered requests, checking for an already matching worker/file/token before insertion. Keep terminal/deleted linked evidence for recovery. Do not revive terminal inspections.
- [x] Validate current pending/running requests have job references or explicit recoverable failure evidence; abort unexplained inconsistencies. Drop `media_inspection_events` only after conversion. Refuse down; use backup restore for reversal.
- [x] Remove the dispatcher, adapter, port, schema and `inspection_outbox_dispatcher` flags. Preserve the Music dispatcher and both video dispatchers.
- [x] Replace dispatcher-only tests with direct atomic creation/recovery assertions; preserve relevant concurrent/failure regressions. Check Music tests and fixtures that formerly dispatched inspection events.
- [x] Verify empty upgrade, seeded upgrade and full fresh migration chain. Compare stable IDs and existing job IDs before/after; run recovery against migrated never-started requests.

## Task 3: Verify and document this release

- [x] Run `mix test test/bolognesa/libraries test/bolognesa/music test/bolognesa/movies test/bolognesa/series` and the new migration verifier using the existing disposable-verifier invocation convention.
- [x] Run `mix precommit`; review transaction rollback, concurrency, notifications and source privacy.
- [x] Add the shared architectural decision, update 0004, decision index, backend convention, deployment guide and status. Describe Music/video outboxes as still present.
- [x] Confirm only the inspection outbox has disappeared, pending work survives upgrade, UI contracts are unchanged and later plans are unnecessary for startup.

## Acceptance

Every newly committed inspection request has its matching Oban job. Failed insertion rolls back the entire inventory batch. No inspection dispatcher/table/runtime reader remains. Existing work survives the offline upgrade. Focused checks, verifier and precommit pass.

# Plan 2: direct Music import jobs

Status: proposed; implementation has not started.

**Design:** [Shared ownership, invariants, migration and verification policy](direct-jobs-design.md). Read it before this plan.

**Execution:** sequential implementation with the executing-plans workflow. This plan ends in a releasable change. No deployment is authorized by this document.

## Scope and starting point

Execute after plan 1. Replace Music refresh delivery only; Movies and Series identification outboxes remain. Preserve music grouping, track IDs, browsing, playback, retries and public user-facing APIs.

## Contracts

### Music requests

Add this trusted infrastructure integration to the Music facade, following the existing transaction-aware Movies/Series precedent:

```elixir
@type transaction_repository :: atom()
@type import_request :: %{
  required(:file_id) => pos_integer(),
  required(:revision) => pos_integer(),
  required(:inspection_token) => String.t()
}

@spec request_import_in_transaction!(transaction_repository(), import_request()) ::
        :requested | :unchanged | :stale
```

Require an active transaction; raise on invocation outside one. Propagate write failures to the enclosing transaction. The facade delegates to Music's EctoImportRepository, which revalidates music ownership, availability, successful current inspection, token, revision, and the presence of an audio track. Invalid observations return `:stale` and write nothing.

For a new current token, create/reset `music_imports` as pending and insert/link RefreshWorker atomically. For a repeated current token with existing pending, running, succeeded, or failed state, return `:unchanged`; ordinary redelivery must not retry a terminal failure. Explicit authorized retry remains the operation that reopens a failed request.

Libraries calls this facade after saving a successful inspection, inside its existing transaction. Libraries passes scalar references and never imports Music workers, schemas, repositories, or domain models.

### Music job ownership and locking

Keep the existing RefreshWorker payload (`file_id`, `revision`), so already queued jobs remain readable. Persisted import token and job ID determine request ownership. `begin_attempt/3` must require an existing current pending/running request with the same job ID; it must not create a request from whatever inspection happens to be current. A job from a previous token at the same revision becomes a harmless stale result.

Use the lock order file → inspection → import for request, retry, execution, completion, and recovery. Libraries already holds the file and inspection locks when handing off. Reuse one request-writing helper for initial requests and retries, while keeping their different terminal-state policies explicit. All writer queries must use the supplied repository in the transaction-aware integration.

Music recovery reads `music_imports` joined to current observations and Oban jobs. A pending request exists before any worker starts, so remove event-based `unstarted_ids`, `recover_unstarted`, and `recover_event`. Missing/discarded/cancelled/completed jobs retain visible failure semantics; healthy scheduled/available/retryable jobs remain eligible to run. Filter eligibility before applying the batch limit.

## Task 1: Give Music a durable pending request at handoff

**Modify:**
- `lib/bolognesa/music.ex`
- `lib/bolognesa/music/infrastructure/repositories/ecto_import_repository.ex`
- `lib/bolognesa/music/infrastructure/jobs/refresh_worker.ex` only if needed to enforce ownership.
- `lib/bolognesa/libraries/infrastructure/repositories/ecto_inspection_repository.ex`
- `test/bolognesa/libraries/music_refresh_outbox_test.exs` → rename to `music_import_handoff_test.exs`.
- Existing import/retry/recovery tests under `test/bolognesa/music/`.

**Deliverable:** Successful audio inspection, pending import, and linked job commit together; Music recovery needs no event for new requests.

- [ ] Add facade/adapter tests for accepted handoff, wrong content type, missing file, stale token/revision, no audio, and a call outside a transaction.
- [ ] Assert repeated current-token delivery creates one request/job, preserves terminal state, and creates no duplicate track. Cover concurrent delivery and inspection replacement without a revision change.
- [ ] Inject failed job insertion and failed import persistence. Assert the successful inspection result and all handoff writes roll back together; Libraries emits no success hint for rolled-back work.
- [ ] Implement the facade contract and request-writing helper using the supplied repository and the existing lock order.
- [ ] Replace MusicRefreshEventSchema insertion in inspection completion with the Music facade call. Persist successful inspection before revalidating it through Music in the same transaction.
- [ ] Tighten begin_attempt to reject absent requests and mismatched job IDs, including old jobs at the same file revision after a forced reinspection.
- [ ] Preserve authorized retry behavior: pending/running/succeeded requests are not duplicated; failed current imports can be explicitly retried with a new linked job.
- [ ] Simplify recovery to current persisted import requests. Verify never-started jobs that are deleted/discarded become visible failures without event lookup; healthy waiting jobs do not consume the recovery batch budget.
- [ ] Run `mix test test/bolognesa/music test/bolognesa/libraries/music_import_handoff_test.exs test/bolognesa/libraries/inspect_media_file_test.exs`.

## Task 2: Migrate Music requests and remove event-based recovery

**Create:** `priv/repo/migrations/<timestamp>_replace_music_refresh_outbox_with_jobs.exs` and `scripts/verify_music_import_jobs_migration.exs`.

**Remove:**
- `lib/bolognesa/libraries/application/ports/repositories/music_refresh_outbox_repository.ex`
- `lib/bolognesa/libraries/infrastructure/repositories/ecto_music_refresh_outbox_repository.ex`
- `lib/bolognesa/libraries/infrastructure/jobs/music_refresh_dispatcher.ex`
- `lib/bolognesa/infrastructure/persistence/music_refresh_event_schema.ex`

**Modify:** `lib/bolognesa/application.ex`, `config/config.exs`, `config/test.exs`, `config/screenshots.exs`, `test/bolognesa/libraries/music_refresh_recovery_test.exs`, affected fixtures/scripts.

- [ ] Seed undelivered/delivered events with waiting, executing, terminal and deleted jobs; absent/old-token/current pending/running/succeeded/failed import states; non-audio, missing, changed-revision and same-revision/new-token observations.
- [ ] For current successful audio events, preserve matching current import state. When no current-token request exists, materialize it from the legacy event/job: pending for a new undelivered job, running for an executing linked job, and failed for terminal or deleted delivered jobs. Preserve linked job IDs and failure semantics.
- [ ] Never replace current-token succeeded/failed imports or schedule duplicates. For an old-token import, establish current event eligibility before replacing its attempt state. Preserve catalog track data independently of attempt replacement.
- [ ] Validate recoverable state for every eligible event, then drop `music_refresh_events`. Refuse down and document backup restoration.
- [ ] Remove event-based recovery helpers and event readers completely. Remove the dispatcher and its flags while preserving Music ImportReconciler and video dispatchers.
- [ ] Verify empty/seeded upgrades, fresh setup, old payload execution and recovery before the worker's first attempt. Confirm old-token same-revision jobs cannot take over the migrated request.

## Task 3: Verify and document this release

- [ ] Run `mix test test/bolognesa/music test/bolognesa/libraries` and the migration verifier, then `mix precommit`.
- [ ] Review request ownership, supplied repository usage, file → inspection → import lock order, terminal retry policy and transaction rollback.
- [ ] Update the shared decision, 0018, backend convention, deployment guide and status. Confirm only Music owns its pending import state and recovery needs no Libraries event table.

## Acceptance

Inspection success, pending import and linked job are atomic. Duplicate handoffs preserve terminal state. Deleted never-started jobs become visible failures. Old-token jobs at the same revision are stale. No refresh event infrastructure remains. Existing catalog data survives upgrade and all required checks pass.

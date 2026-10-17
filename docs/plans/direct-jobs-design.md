# Direct durable jobs: shared design

Status: proposed; no implementation or deployment has started.

## Outcome

Create Oban jobs in the same PostgreSQL transaction as the requests they execute. Remove intermediate outboxes where both request and job share the database. Preserve existing data, recovery, bounded processing, and observable behavior.

## Independent deliveries

1. [Libraries inspection](01-library-inspection-jobs.md): affects movie, series, and music files. Removes only `media_inspection_events` and its dispatcher.
2. [Music import](02-music-import-jobs.md): persists a pending import and linked job when accepting a successful current audio inspection. Removes only `music_refresh_events` and its dispatcher.
3. [Movies and Series identification](03-video-identification-jobs.md): each owner creates jobs through its existing request writer. Removes its own identification event table and dispatcher.

Execute in that order. Each plan must finish as a separately verifiable and deployable release; no plan requires unfinished code from the next. Rehearse both direct upgrade to the final release and upgrades through each intermediate release. Deployment remains a separately authorized operation.

## Ownership and invariants

Libraries owns sources, inventory, scans, and technical observations. Music owns import requests from acceptance onward. Movies and Series retain independent decisions, writers, jobs, recovery and metadata. Cross-context writes enter through public transaction-aware facades; never call another context's internal adapter.

A request and its job commit or roll back together. Use the worker constructor for queue and attempt settings. Save the returned job ID before commit. Provider calls, filesystem traversal, and ffprobe run outside transactions. Supplied repositories must be used consistently; nested transactions must not escape the outer atomic boundary.

Preserve scan generations, request tokens, revisions, wrong-type rejection, durable manual corrections, source privacy, and bounded batches. Jobs are at least once; stale and duplicate execution must be harmless. Music requires persisted request/job ownership even when the revision is unchanged after reinspection.

Keep PubSub as best-effort post-persistence UI hints. Keep existing separate recovery processes. Do not introduce a shared workflow engine, generic repository, universal media model, new dependency, query regrouping, or repository restructuring in these deliveries.

## Migration and release policy

Preserve accounts, IDs, corrections, catalogs, inspection results, and existing jobs. No reset or required rescan. Stop old application instances and workers before migration; mixed-version execution is unsupported.

Each migration converts only its own legacy events into request/job state before dropping its event tables. Use migration-local SQL/data definitions and installed Oban schema contracts, never application modules whose behavior later changes. Process at most 100 event rows per keyset batch. The overall offline transaction can still be long: measure representative backlogs during rehearsal.

Retain matching jobs and terminal/missing-job evidence; do not silently retry failed work. Insert a job only for a current undelivered request that lacks an existing matching job. Ignore obsolete events only after proving current revision/token/type supersedes them. Abort unexplained inconsistent current state. Refuse destructive down migrations explicitly; returning to the old version requires a matching database backup and release.

The implementing release must document validated backup, maintenance window, actual migration and verification commands. Local tests establish neither deployment nor device compatibility.

## Execution and verification

Implement each plan sequentially with the executing-plans workflow. Read the product/status/roadmap, applicable decisions and backend/Elixir/testing/observability/documentation conventions; inspect Git and preserve unrelated work. All plans are proposed and require review before implementation.

For each release: update relevant behavior tests, demonstrate meaningful new regressions fail before implementing them, run focused PostgreSQL checks, its migration verifier, and `mix precommit`. Review atomicity, lock order, stale results, bounded recovery, private SQL/job error fields and data preservation. Record actual results and next steps in `docs/status.md`.

Add a direct-job architecture decision at the first delivery; qualify exactly which outboxes have been replaced. Update 0004 after plan 1, 0018 after plan 2, and 0019 after plan 3; update backend conventions and the deployment guide at each release. Preserve historical migration files. Remove these temporary notes after completion and retain lasting decisions.

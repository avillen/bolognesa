# Execution ledger: direct durable jobs

Branch: refactor/direct-jobs. Base: 658d42e. Workspace: .worktrees/direct-jobs.

Pre-flight: inspection job linkage feeds existing recovery; Music requires pending state before tightening job ownership; video writers cover scan/backfill/retry. No conflicting payload contracts.
Ruling: keep execution records under docs/plans rather than tool-specific directories, following project instructions.
Ruling: execute in an isolated worktree, preserving untracked plans in the original checkout. User requested all three plans; do not merge or deploy automatically.

Inspection RED: pipeline failed because the committed inspection had nil job_id. GREEN: 40 inventory/pipeline/recovery tests passed. Initial broad baseline was interrupted by a test file rename while compilation was running; no baseline success claimed.

Plan 1 complete: 334 focused tests + 1 skipped; full precommit 520 passed + 1 skipped; disposable inspection migration empty/seeded >100 cases passed. Initial Credo alias findings fixed. Test suites now run sequentially on bolognesa_test_direct_jobs to avoid concurrent committed-fixture interference.

Plan 2 RED: 4 handoff tests failed (missing pending import and facade; job rejection did not roll back inspection); ownership regression allowed an unrequested job to adopt the current token. Implementing pending state and strict job ownership.
Ruling: use worker changesets with the supplied transaction repository for cross-context job insertion. These jobs have no Oban uniqueness options; database notifications and transactional insertion remain active, without switching to a configured repository outside the caller's transaction.
Ruling: bind Music refresh reads to the attempt token as well as revision. A worker that began before a same-revision reinspection must not refresh the replacement observation. Existing two-argument refresh calls remain supported.

Plan 2 broad precommit: 524 passed + 1 skipped after correcting committed-fixture cleanup (Music imports use a restrictive file foreign key).
Ruling correction: installed Oban removes the insert notification trigger. A real LISTEN/NOTIFY regression exposed direct repo.insert! bypassing queue notification. Use supported Oban.insert with Ecto.Multi executed by the supplied repository, preserving both the outer transaction and notifier. Apply the same mechanism to video owners.

Plan 2 complete: notifier regression RED (empty LISTEN mailbox) → GREEN through Oban.insert/Ecto.Multi. 35 focused tests passed; final precommit 525 passed + 1 skipped. Music migration empty/seeded and mismatched-link rollback passed.

Plan 3 RED: all 10 direct-job/rollback/transaction-boundary tests failed against event-based writers. Both owner writers now create/link jobs through Oban.insert/Ecto.Multi on the supplied repository. No runtime event schemas, readers, dispatchers or flags remain.
Ruling: pin the historical content-context verifier to its target migration so it continues testing that historical schema; the new direct-job verifiers exercise the full chain through each new release.

Plan 3 focused verification: 163 passed. An unboxed Series constraint-injection test lacked its committed tag and blocked on its own sandbox's Oban lock; corrected the tag and reran in a fresh dedicated test database. All three migration verifiers now execute migrated jobs and deleted-before-start recovery, preserve stable data and manual associations, and abort/rollback earlier batches on mismatched job linkage. Historical content verifier passed two pinned rebuilds. Final integrated precommit/review pending.

# Proposed refactor plans

These are temporary working documents, not implemented behavior.

Read the [shared design](direct-jobs-design.md), then execute each independently releasable plan in order:

1. [Direct inspection jobs in Libraries](01-library-inspection-jobs.md) — movie, series, and music technical inspection.
2. [Direct Music import jobs](02-music-import-jobs.md) — pending imports, delivery, and recovery.
3. [Direct Movies and Series identification jobs](03-video-identification-jobs.md) — owner-specific requests, backfill, retries, and recovery.

Each release preserves existing data and pending work through its own offline migration. Remove completed working notes after retaining the lasting architecture decisions.

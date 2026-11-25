# 0032. Account-owned watched movies in Movies

Status: Implemented locally.

## Context

Accounts need to know which movies they have watched, as Series does for entries
in [0029](0029-series-watched-entries.md). A movie can have several physical
versions, and rescans or replacements change the files without changing the movie.

## Decision

Movies owns one `watched_movies` row per account and catalog movie, with only
`last_watched_at`. The composite primary key makes the atomic upsert retain the
greatest timestamp. The global persistence schema follows
[0008](0008-global-persistence-schemas.md).

After account authorization, Movies requires an available file with a confirmed
automatic or manual identification to the reported movie. Missing or unrelated
files record nothing. The row references the movie, not the file, so watched state
survives rescans, missing files and version replacements.

The browser reuses the shared playback observation and qualifying threshold from
0029 unchanged. The movie LiveView applies the same attempt/file correlation and
per-attempt deduplication as the episode page through a shared LiveView helper.
Recording failures emit sanitized Movies observations through the shared Events
contract. Movie details return the account's `last_watched_at`, if any.

A movie has no parts or episode order, so there is no watch count, history, resume
position or Continue target.

## Consequences

Account or movie deletion cascades its rows; deleting a file does not. Identification
corrections to another movie do not move earlier state. The additive migration has
no backfill and refuses rollback while rows exist. Apply the migration before
activating code. Automated checks do not establish deployment or device support.

# 0029. Account-owned watched season entries in Series

Status: Implemented locally.

## Context

Accounts need durable watched state without viewing history or consumption analytics.
Music already retains one latest listening timestamp per account and track. Video
requires the episode/part identities from [0013](0013-series-and-multiple-episode-associations.md)
and [0025](0025-consecutive-episode-parts.md), independently of temporary position
recovery in [0024](0024-tab-playback-recovery.md).

## Decision

Series owns one row per account, catalog episode and optional numbered part, with
only `last_watched_at`. A null part represents an unsplit entry. The unique index
uses `NULLS NOT DISTINCT`; atomic Ecto upserts retain the greatest timestamp.
The global persistence schema follows [0008](0008-global-persistence-schemas.md).
`WatchedEntry` composes the `SeasonEntry` identity and its latest watched timestamp.

After account authorization, Series requires an available file with a confirmed
automatic/manual association to the reported episode. Missing or unrelated files
record nothing. A part marks its own entry; a whole-file version marks all known
parts, including unavailable ones, or the unsplit entry when there are no parts.
A multi-episode file applies the whole-file rule to every associated episode.

The browser qualifies after at least 120 seconds of observed playback and reaching
90% of whole-file duration or the end. Shared browser-independent observation code
accumulates plausible media advancement bounded by monotonic wall time, excluding
pauses, seeks and preparation gaps. Music and video supply their own qualifying
rules; failures retry after 15 seconds while the same selection remains active.
HLS uses whole-file offsets. Source changes break sampling; new attempts reset it.

The LiveView correlates the current attempt/file and deduplicates successful saves.
Acknowledgements permit retries; late failures cannot affect a new attempt. Recording
failures emit sanitized Series observations through the shared Events contract.
This is best-effort client observation, not proof of consumption. There is no count,
history, source reference, manual flag, durable attempt log or cross-device position.

## Consequences

Watched state follows catalog identity across rescans, missing files, renames,
replacement media and identification corrections; it does not transfer to another
episode. Changed part layouts retain historical keys without inferred conversion.
Account or catalog-episode deletion cascades its rows. Reads use episode, season
or single-series scope and retain unavailable and historical entries.

The additive migration has no backfill and refuses rollback while watched rows
exist. Its index syntax requires PostgreSQL 15+; the project uses 17. Apply the
migration before activating code. Original media remains untouched. Automated
PostgreSQL and browser-module checks do not establish deployment or device support.

# 0029. Account-owned watched season entries in Series

Status: Persistence and playback recording implemented locally. Display, manual actions,
and Continue are separate tasks under [#83](https://github.com/avillen/bolognesa/issues/83).

## Context

Each account needs to distinguish watched season entries and eventually return to a
series. Music already records one latest listening timestamp per account and track.
Video needs a different qualifying threshold and the episode/part semantics from
[0013](0013-series-and-multiple-episode-associations.md) and
[0025](0025-consecutive-episode-parts.md). Temporary position recovery in
[0024](0024-tab-playback-recovery.md) remains separate from durable account state.

## Decision

Series owns watched entries, consistent with the content ownership in
[0019](0019-content-context-boundaries.md). Store one row in `series_watched_entries`
per `(user_id, episode_id, part_number)` with only `last_watched_at`. A null part is
an unsplit season entry; numbered parts are 1–100. PostgreSQL uniqueness uses
`NULLS NOT DISTINCT` to protect unsplit entries under concurrency. Upserts use the
greatest existing or incoming timestamp, as Music listening activity does. There
is no count, history, progress position, source file reference, or manual flag.

Catalog identity, rather than inventory path or selected version, owns the state.
Rescans, missing files, renames, replacement media, and identification corrections
do not erase it or transfer it to another episode. Deleting an account or catalog
episode cascades its watched entries. If the observed part layout changes, stored
keys remain historical facts: this change does not infer migration from an old
unsplit entry to newly discovered parts or vice versa.

Resolve the reported file's confirmed associations inside Series after Playback
reauthorizes the episode/file through its public facade. One part marks that
entry. A whole-file alternative marks every currently known numbered part of its
episode, including unavailable parts; without numbered parts it marks the unsplit
entry. A multi-episode file marks the current entries of every associated episode,
using the same whole-file rule. No arbitrary episode IDs from the browser become
a write batch. Resolution and the read-side season list use the same entry query.

The browser reports qualifying playback for the issued attempt when whole-file position
reaches at least 90% of duration (or the media ends), and at least 120 seconds of
playback have actually been observed in that attempt. Accumulate plausible media
advancement bounded by monotonic wall time; pauses, seek jumps, source replacement,
and preparation gaps do not count. HLS offsets use the whole-file timeline, not
segment time. New attempts reset the observation. A seek or automatic delivery
recovery within the same attempt retains accumulated time but breaks sampling.
A full reload starts a fresh attempt even when temporary recovery restores position.

The episode LiveView accepts only the current ready attempt UUID and file and
suppresses duplicate successful recordings for that attempt. Report before the
existing ended event advances to the next entry. This follows Music's best-effort
client-observation approach; it cannot prove consumption or prevent a modified
client from claiming a viewing. The LiveView replies with `ok: true` after a successful
save or a duplicate successful report, and `ok: false` for a failed or invalid report.
Following Music's acknowledgement and retry pattern, a failed reply permits one retry
after 15 seconds while the same attempt remains selected. Late failures from a previous
attempt cannot change the current observation. Successful saves remain deduplicated.
The application emits sanitized `[:bolognesa, :series, :watched_entries, :failed]`
observations through the shared Events contract on recording failures. No browser
storage, durable attempt rows, new endpoint, or Playback-owned watched state is added.
Music's document lifetime in [0027](0027-persistent-music-player.md) is unchanged.

## Contracts for sibling tasks

`Series.list_watched_entries(actor, scope)` authorizes the account and returns
`{:ok, [WatchedEntry]}`. Scope is `{:episode, id}`, `{:season, id}`, or `{:series, id}`,
with a single ID. Each model has `episode_id`,
nullable `part_number`, and `last_watched_at`. Reads retain unavailable and historical
keys, order by episode ID then part with null first, and return an empty list for
no activity or a missing scope. Failures return an error, never an empty success.
Continue must derive catalog order explicitly. The index shelf's query belongs to
[#87](https://github.com/avillen/bolognesa/issues/87).

Within Series, `WatchedEntriesReader` declares these reads and
`fetch_played_entries(episode_id, file_id)`. `WatchedEntriesRepository` declares
`upsert(user_id, entries, watched_at)` and `delete(user_id, entries)`, accepting
explicit `SeasonEntry` values with `episode_id` and nullable `part_number`.
Both writes are atomic single SQL statements for the explicit entries;
empty batches are no-ops. Upsert preserves the latest timestamp; deletion affects
only the selected account and keys. Application use cases own authorization and
selection. Web callers use the Series facade, never these internal adapters.

These contracts support [watched display (#84)](https://github.com/avillen/bolognesa/issues/84),
[manual marking (#85)](https://github.com/avillen/bolognesa/issues/85), and
[Continue (#86)](https://github.com/avillen/bolognesa/issues/86) without changing the
persistence key. Manual marking will set now; unmarking will delete the row, with
no distinction between manual and observed watching. Continue will exclude season
zero because specials are outside regular narrative ordering, while still allowing
them to be watched and recorded. Continue will order regular entries by season,
episode and part, use the latest watched timestamp with the furthest entry as the
tie-breaker, and retain known unavailable targets. These UI actions and derivation
are not implemented by this record's persistence task.

## Activation and consequences

The migration adds an empty table and indexes with no catalog backfill. It does
not rewrite existing media or catalog identities. Apply it before activating code.
Rollback refuses to discard nonempty watched state, matching Music's preservation
rule. PostgreSQL 15+ is required by the unique-index syntax (the project uses 17).

Automated PostgreSQL and browser-module tests cover persistence, authorization,
resolution, attempt correlation, and observation thresholds. They do not establish
deployment or real-device compatibility.

# 0018. Local music identities and durable import

Status: Implemented. Deployment evidence and playback verification limits are tracked in [project status](../status.md).

[0019](0019-content-context-boundaries.md) clarifies that Music remains an independent content owner. Movies and Series replace the former video Identification boundary; music/video selectors and queues remain separate as described here.

## Context

Music needs local identities independent of TMDb, musical grouping, and recovery after technical inspection. Reusing video catalog identity would require fictitious external provider IDs and would mix playback selectors whose numeric IDs overlap.

## Decision

- Libraries owns music sources, inventory, typed extension policy, and bounded FFprobe observations. Discovery accepts MP3, M4A, AAC, FLAC, OGG, Opus, and WAV. Music never enters the Identification request or backfill boundary.
- Allowlist title, artist, album artist, album, disc/track numbers, and date/year from format and audio-stream tags. Trim valid UTF-8 strings to at most 512 bytes; invalid/oversized values become absent. Numbers are positive and bounded; titles fall back to safely displayed filenames. Video keeps discarding musical/private tags, and embedded artwork is not imported.
- Music owns stable local track IDs, one track per inventory file, and local artists/albums. Metadata refresh changes memberships without replacing a track ID. Copies remain distinct. Artist keys are library-local Unicode case folds. Album keys add raw source parent, normalized title, and normalized album artist; an absent artist uses a non-null empty key. Missing album tags do not invent an album.
- Successful current music inspection and a refresh event commit together. Libraries dispatches minimal file/revision jobs and records their IDs with delivered events atomically. Music owns import state and retries, and may read event references to recover jobs that never wrote import state.
- Import locks inventory, inspection, then its own state. It rechecks revision, successful token, availability, library type, and audio presence. Forced inspection at the same revision invalidates earlier tokens. Duplicate/stale delivery cannot replace current metadata or downgrade a successful import. Recovery filters obsolete observations before applying batch limits and includes jobs that failed before import state was written. It uses batches of 100, three attempts, a single import worker per instance, five-second dispatch, and thirty-second reconciliation; stale executing work requires both timestamps older than sixty seconds.
- Authorized reads include pending and failed files without tracks, pagination bounded to 50 items per page, literal search, and library scope. Artist and album groups with no available files are omitted. Explicit retries recover terminal import errors; probe failures use library reanalysis.
- Playback selects music separately and serves authorized direct audio with shared descriptor validation and byte ranges. The native player belongs to the music page. Individual selection requires native play; explicit album playback requests browser playback and advances on completion, with visible feedback if autoplay is blocked. Album queues contain at most 500 tracks, include pending and failed tracks so playback can report unavailable entries, preserve the album order, reauthorize each selected track, and stop on an unavailable item with a next control. URL patches within the music page preserve listening; full navigation or reload ends the queue.

## Consequences

The extra music tables and outbox preserve identity and recoverable failures without a generic media framework or new runtime dependency. Conservative album grouping leaves disc-subfolder consolidation, cross-library merging, and recording deduplication for later work. Schema rollback refuses while music libraries exist rather than dropping their records implicitly.

Automated tests establish metadata, persistence, concurrency, and HTTP delivery; they do not establish decoding. Artist and album browsing reuse existing library-local identities. An artist sees albums credited to them or containing their tracks; missing album tags leave songs accessible in the flat list. Album tracks sort by disc number, track number, raw relative path, then track ID, with missing numbers last. Queue editing, continuous playback across other screens, audio conversion, external artwork/identification, manual metadata editing, and saved progress remain separate work. Original files stay read-only.

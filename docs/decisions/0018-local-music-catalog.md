# 0018. Local music identities and durable import

Status: Implemented and deployed. Synthetic PCM WAV playback is verified in screenshot Chromium; other formats and devices remain unverified.

## Context

Music needs local identities independent of TMDb, musical grouping, and recovery after technical inspection. Reusing video catalog identity would require fictitious external provider IDs and would mix playback selectors whose numeric IDs overlap.

## Decision

- Libraries owns music sources, inventory, typed extension policy, and bounded FFprobe observations. Discovery accepts MP3, M4A, AAC, FLAC, OGG, Opus, and WAV. Music never enters the Identification request or backfill boundary.
- Allowlist title, artist, album artist, album, disc/track numbers, and date/year from format and audio-stream tags. Trim valid UTF-8 strings to at most 512 bytes; invalid/oversized values become absent. Numbers are positive and bounded; titles fall back to safely displayed filenames. Video keeps discarding musical/private tags, and embedded artwork is not imported.
- Music owns stable local track IDs, one track per inventory file, and local artists/albums. Metadata refresh changes memberships without replacing a track ID. Copies remain distinct. Artist keys are library-local Unicode case folds. Album keys add raw source parent, normalized title, and normalized album artist; an absent artist uses a non-null empty key. Missing album tags do not invent an album.
- Successful current music inspection and a refresh event commit together. Libraries dispatches minimal file/revision jobs and records their IDs with delivered events atomically. Music owns import state and retries, and may read event references to recover jobs that never wrote import state.
- Import locks inventory, inspection, then its own state. It rechecks revision, successful token, availability, library type, and audio presence. Duplicate/stale delivery cannot replace current metadata or downgrade a successful import. Recovery uses batches of 100, three attempts, a single import worker per instance, five-second dispatch, and thirty-second reconciliation; stale executing work requires both timestamps older than sixty seconds.
- Authorized reads include pending and failed files without tracks, bounded pagination, literal search, and library scope. Explicit retries recover terminal import errors; probe failures use library reanalysis.
- Playback selects music separately and serves authorized direct audio with shared descriptor validation and byte ranges. The native player belongs to the music page and does not autoplay or survive navigation.

## Consequences

The extra music tables and outbox preserve identity and recoverable failures without a generic media framework or new runtime dependency. Conservative album grouping leaves disc-subfolder consolidation, cross-library merging, and recording deduplication for later work. Schema rollback refuses while music libraries exist rather than dropping their records implicitly.

Automated tests establish metadata, persistence, concurrency, and HTTP delivery; they do not establish decoding. Artist/album pages, queue, continuous navigation playback, audio conversion, external artwork/identification, manual metadata editing, and saved progress remain separate work. Original files stay read-only.

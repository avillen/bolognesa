# Project status

Last reviewed: 2026-10-16.

## Implemented behavior

Movies, Series, and Music independently own their content and recovery. Video identities use independent sequences; Playback selects movies and episodes with explicit typed references. Bolognesa supports movie, series, and music libraries; recoverable scanning and technical inspection; TMDb identification and manual corrections; library-scoped catalog browsing; authorized direct playback; and optional FFmpeg/HLS video playback. Original media remains read-only. Scanning and identification are separate steps; automatic lookup requires a runtime TMDb token.

Music supports local tags with filename fallbacks, track/artist/album browsing, search, pagination, import retry, and ordered album playback with previous/next and automatic advance. Listening survives URL patches within music; full navigation or reload ends the queue. Identity, grouping, limits, and recovery contracts live in [decision 0018](decisions/0018-local-music-catalog.md).

Configured libraries appear in the sidebar, including empty ones. Catalog lists and counts follow the selected library; work details and playback versions remain shared across libraries. Library progress refreshes asynchronously after best-effort hints emitted by application use cases following persistence. Lost hints can leave an open tab stale until another hint or reload/reconnect. Notification failure preserves successful persistence; connected-mount subscription failure is not directly simulated.

LiveDashboard requires a verified administrator session for both HTTP and LiveView access in every environment. The mailbox preview is development-only.

## Recorded verification

Current content-context checks and deployment observations are distinguished from earlier device evidence.

- Current local `mix precommit`: 499 tests passed, one skipped; compilation and Credo passed. Coverage includes foreign-type mutation rejection, bounded owner backfill/dispatch/recovery, atomic inventory/request/event and work/association rollback, manual/stale revision races, and equal-ID direct/HLS delivery. A fresh whole-change review found an HLS query-parameter route ambiguity; regression tests reproduced it for both manifests and segments, and the corrected controller uses path parameters exclusively.
- The fixed disposable content-context migration verifier passed two full fresh/reset rebuilds, independent sequence checks, legacy table/function removal, and refused reversal. Both historical migration verifiers passed their seeded and empty cases without requiring obsolete application workers or writers.
- `make check-screenshots` passed with unchanged captures, including synthetic PCM WAV playback, seek/pause, album advance, previous/next, music navigation continuity, and stopping on exit in Chromium 140. Three audio-hook tests and five screenshot-comparator tests passed. These checks do not establish real-device or other-format decoding.
- Music checks cover metadata, current-token/revision validation, concurrent imports, outbox atomicity and recovery, authorized retries, literal searches, stale UI responses, bounded queues, and authenticated MIME/range delivery. Synthetic controller bytes establish delivery rather than decoding.
- Published [application CI](https://github.com/avillen/bolognesa/actions/runs/38862632019), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/38862631689), and [image CI](https://github.com/avillen/bolognesa/actions/runs/38862631637) passed for `502f5e2097b64c576b0dacb06265bf5a5048f9ca`. The incoming six-commit range passed the pinned Gitleaks scan with no findings.
- Deployed that commit with `make deploy-release` using verified image `ghcr.io/avillen/bolognesa@sha256:4758f7f90019980bd39458182ce5cf040f5ac2a61564e54845f9d3961f524a4e` on ARM64. The old application was stopped, a validated pre-reset backup and its previous image reference were retained, and only the configured application database was rebuilt before normal release migration/startup/health checks. The pre-reset backup was validated again after activation; the later empty-database backup does not replace it.
- Post-deployment checks verified independent owner tables, absence of the old central tables, healthy PostgreSQL, all four owner dispatcher/reconciler processes, HTTP 200 at `/setup`, and HTTP 401 for unauthenticated media. Normalized mount configuration and database configuration matched their pre-deployment values; all three source mounts remain read-only. Authenticated browsing and real-media playback after reimport have not been checked on this rebuilt installation.
- Local Compose startup, migrations, and initial setup were verified on x86_64. A compatible MP4 played in Chrome on a private deployment. Music inspection handles attached cover art without rejecting valid audio.

## Limits and next work

The [content-context change](decisions/0019-content-context-boundaries.md) is implemented, reviewed, published, and deployed. The agreed whole-database rebuild removed accounts, library configuration, corrections, imported catalog data, and Oban jobs while preserving original media mounts. The installation is at initial setup: create the administrator, register the sources using their existing internal paths, then scan and identify again. The [deployment guide](../deploy/compose/README.md#one-time-content-context-rebuild) documents the rebuild and backup/restore contract.

Native ARM64 startup and basic HTTP behavior are now verified; mobile/TV playback, manual keyboard/touch interaction, other audio format decoding, and performance across real media remain unverified. A reported series inspection failure was not reproduced locally; retry library analysis and inspect the bounded warning fields (`file_id`, failure stage, reason) to diagnose it. Its resolution remains unconfirmed.

Playback progress is not persisted across sessions. Multi-episode files play in full from the beginning. Music has no conversion, queue editing, saved progress, or playback across other screens. The next music outcome is queue editing or continuous playback across authenticated navigation; acceptance outcomes are in the [roadmap](roadmap.md). The generic HTTP deployment is for trusted private networks and must not be exposed directly to the Internet.

The project uses MIT licensing. A recorded full-history Gitleaks scan found no unallowlisted findings after public-history cleanup; CI scans incoming commits. A final public-release privacy review remains necessary because secret scanning does not detect every private detail.

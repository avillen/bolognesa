# Project status

Last reviewed: 2026-10-12.

Bolognesa is an early self-hosted media center built with Phoenix LiveView, Ecto, PostgreSQL, and Oban. The repository includes local Docker Compose development and a generic Linux Compose deployment. Movie and series libraries, scanning, technical inspection, TMDb identification, catalog browsing, authorized direct playback, and an optional FFmpeg/HLS path are implemented.

The sidebar lists configured libraries by their stored names with movie or series icons, including empty libraries. Catalog lists, searches, pagination, and availability counts are scoped to the selected library. Detail navigation retains that selection; work details and playback versions remain shared across libraries. Creating a library updates the sidebar immediately.

The library screen refreshes scan progress and inspection counts asynchronously after hints explicitly emitted by application use cases through `LibraryStatusNotifier`, following successful persistence. Recovery use cases also notify changes confirmed before a later recovery transaction fails. Repositories return persisted results and never publish PubSub hints. Subscriptions and reads are independently authorized; PostgreSQL remains authoritative. Hints are best effort: a lost notification or interrupted subscription can leave an open tab stale until another hint or reload/reconnect.

The shared `Infrastructure.Services.PubSubNotifications` transport accepts context-owned topics and messages and normalizes availability errors. Libraries retains its status payload, logging, and best-effort delivery policy.

LiveDashboard is available at `/dev/dashboard` in all environments. HTTP requests and LiveView mounts require a verified administrator session; the mailbox preview remains development-only.

## Verification and limits

- Local Docker Compose startup, database migrations, and the first setup page have been verified on an x86_64 host. This does not verify native ARM64 behavior.
- `mix precommit` passed locally with 404 tests passing and one skipped. Coverage includes administrator dashboard access, rejection of anonymous visitors, members and revoked sessions, library-specific catalogs and navigation, library creation and read failures, application-owned notification delivery after commit, silent repository writes and stale attempts, cross-tab updates, inspection completion and recovery back to pending, follow-up reads for hints received during a refresh, partial recovery failures retaining earlier commits, and shared PubSub topic isolation. Committed recovery fixtures have independent cleanup assertions. README screenshots were regenerated, visually reviewed for the library catalogs, and verified with `make check-screenshots`. CI configuration is present; its latest GitHub run should be checked before relying on it for a release.
- An unavailable notification adapter is verified to preserve a successfully persisted scan request and its queued job. Subscription failure during connected mount is not directly simulated.
- A compatible MP4 has played in Chrome on the private deployment. Playback controls, mobile and TV playback, and performance across media formats still need hands-on verification.
- Scanning discovers files; identification is a separate step. Automatic metadata lookup requires a TMDb read token.
- Playback progress is not persisted across sessions. Multi-episode files play in full from the beginning.
- The generic HTTP deployment is intended for a trusted private network and must not be exposed directly to the Internet.

## Music work in preparation

Local music listening has an approved design for incremental delivery: individual tracks first, then artist/album browsing and a queue, followed by continuous playback during navigation. The [approved design](music-playback-design.md) evaluates targeted discovery, inspection, and playback refactors. The [implementation plan](music-playback-plan.md) covers the first delivery. Implementation is deferred at the maintainer's request; resume by reviewing the plan, selecting an execution method, and checking the current code and baseline tests. No music code or migrations have been added. Existing verification above applies to movie and series behavior only.

## Before the first public release

The repository now uses the MIT License. The history on `main` has been rewritten to remove old operational notes, private deployment files, local and NAS paths, internal addresses, and personal commit email addresses. A full-history Gitleaks scan reports no unallowlisted findings; `.gitleaksignore` records two exact matches for fixed development/test signing keys, which are not used in production. CI scans incoming commits for known credential patterns, but it does not replace a review for personal paths, addresses, or operational details.

The public-facing README and contributor guide describe local setup. The README includes a selected screenshot gallery and a foldable gallery of all 15 user-facing screens, generated from synthetic sample content. `make screenshots` rebuilds the images with an isolated database and browser-generated video; CI checks that committed captures stay current. No personal media files or paths are included. See the [roadmap](roadmap.md) for open product work and [decisions](decisions/README.md) for architectural context.

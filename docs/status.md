# Project status

Last reviewed: 2026-10-25.

## Implemented behavior

Video playback now keeps one same-tab `sessionStorage` checkpoint, scoped to viewer,
content and physical file, for up to 12 hours. Position updates every three seconds
and on significant media/page transitions; reload recovery preserves pause, clears
completed playback and works with direct video and authorized HLS offset replacement.
Diagnostics add document IDs, navigation type, page/network/socket lifecycle,
media readiness, 30-second progress samples and up to eight replayed unacknowledged
observations. Historical samples have a separate bounded budget; late acknowledgements
from destroyed hooks cannot overwrite current evidence. See
[decision 0024](decisions/0024-tab-playback-recovery.md).
Local `mix precommit` passed compilation, formatting, Credo and 638 tests with one skipped;
Node checks passed 37 tests. The production-player browser harness passed in
Chromium 155 with synthetic MP4/HLS, including actual direct reloads, playing/paused
recovery and one HLS global-offset recovery request. Focused LiveView/diagnostic checks
passed 20 tests, including paused HLS recovery through the real backend operation.
The independent review's delayed-acknowledgement finding was reproduced and fixed;
rejected recovery and batched historical progress also have regression coverage.
These changes are published and deployed as `22853b4eb770fb89e3e01a24c85cceb033c7355a`;
release verification is recorded below. Target iPhone playback and the cause of the
reported page recreations remain unverified. Next step: representative playback/reload
checks on the target browser.

Movie detail now follows the episode playback layout: a compact title/year heading,
a prominent player, a shared expandable synopsis, and versions inside playback options.
The selected version is indicated and playback errors offer the existing retry action.
The movie catalog is unchanged. Local `mix precommit` passed compilation, formatting,
Credo and 635 tests with one skipped; `node --test assets/test/*.mjs` passed 23 tests.
`make screenshots` passed desktop/mobile browser checks, including movie playback and
manual-correction navigation; the movie detail/player captures were updated and visually
reviewed. Included in the deployed recovery release; real-device verification is pending.

Movies, Series, and Music independently own their content and recovery. Inspection and content requests now commit directly with their linked Oban jobs; the four intermediate event tables and polling dispatchers have been removed. Video identities use independent sequences; Playback selects movies and episodes with explicit typed references. Bolognesa supports movie, series, and music libraries; recoverable scanning and technical inspection; TMDb identification and manual corrections; library-scoped catalog browsing; authorized direct playback; and optional FFmpeg/HLS video playback. Original media remains read-only. Scanning and identification are separate steps; automatic lookup requires a runtime TMDb token.

Compatible video playback now prepares at least 12 seconds of published HLS segments before
starting or completing a seek, with a nonempty completed-playlist exception for short
endings. FFmpeg permits a 12-second initial read burst before real-time pacing; the
playlist retains 12 entries and hls.js starts at the session beginning with a three-segment
synchronization distance. Browser diagnostics record buffer waits, recovery durations,
and contiguous buffered media, subject to the existing observation cap. Performance on
representative media on the target server remains unverified.

Video startup uses one backend preparation call for source selection and direct or HLS
preparation, avoiding a repeated source query. The transcode manager separates resource
preparation from process launch, validates replacements before closing the current session,
and removes unused temporary-root state. Directory permission and launch failures clean up
new temporary directories; failed seeks retain the previous session reference for cleanup.
The current naming uses `TranscodeStrategy`, `:audio_only` and `:full_transcode`, and calls
temporary HLS work a transcode session. Authorization, revision checks and the one-process
limit remain in place. Movie and episode playback options show whether playback is direct,
converts audio, or converts video and audio, based on the active session; conversion errors
remain visible without a misleading mode label. Included in the deployed recovery release.
The naming refactor passed `MIX_TEST_PARTITION=_playback_names_final mix precommit`
with compilation, formatting, Credo and 635 tests with one skipped; `node --test assets/test/*.mjs`
passed 23 tests. Included in the deployed recovery release.
For the playback mode indicator, `mix precommit` passed compilation, formatting, Credo,
and 635 tests with one skipped. Included in the deployed recovery release.

Music supports local tags with filename fallbacks, track/artist/album browsing, search, pagination, import retry, and ordered album playback with previous/next and automatic advance. Listening survives URL patches within music; full navigation or reload ends the queue. Identity, grouping, limits, and recovery contracts live in [decision 0018](decisions/0018-local-music-catalog.md).

Mobile navigation uses a compact header and an accessible menu containing named libraries and account links; desktop retains its sidebar. Series browsing has secondary library options, compact search and episode cards, expandable synopses, and contextual return links carrying catalog search, pagination, and library context. Catalog and season scroll positions are bounded per tab. Episode details use a compact series/season breadcrumb, episode title and selected-version duration above the player. Manual previous/next links follow numeric episode order within the season, including unavailable episodes, and preserve return context. The expandable synopsis and localized original air date follow the player; technical/version options remain collapsed, version selection and playback retry remain available, and unavailable episode details are retained. Automatic advance uses `Series.fetch_next_available_episode/3` to skip all episodes in the completed file and select the next available episode, including across seasons. Same-season advance preserves the season return page; crossing seasons resets it. The existing opening logo remains visible until the first frame loads.

Episode redesign verification: `mix precommit` passed compilation, formatting, Credo, and 626 tests with one skipped; `node --test assets/test/*.mjs` passed 23 tests. `make screenshots` regenerated the desktop/mobile episode captures and passed the Chromium 140 synthetic-media/navigation checks. Added browser assertions verify 16:9 layout and long-series breadcrumbs without overflow at 320, 390, 768, and 1440 px, and that expanding the synopsis retains the player element. `make check-screenshots` passed against the updated captures; independent code review found no issues. Real-device interaction and representative-media playback remain unverified. No known redesign blockers remain. Next step: validate touch/keyboard interaction and representative episode playback on target devices.

Configured libraries appear in the sidebar, including empty ones. Catalog lists and counts follow the selected library; work details and playback versions remain shared across libraries. Library progress refreshes asynchronously after best-effort hints emitted by application use cases following persistence. Lost hints can leave an open tab stale until another hint or reload/reconnect. Notification failure preserves successful persistence; connected-mount subscription failure is not directly simulated.

LiveDashboard requires a verified administrator session for both HTTP and LiveView access in every environment. The mailbox preview is development-only.

Application Telemetry now covers Accounts mutations and operational session failures;
Libraries scanning, inspection, recovery, and degraded notifications; Movies and Series
identification, corrections, provider failures, and recovery; Music imports, retries,
and recovery; and failed direct audio/video delivery. Events are sanitized before
emission and reported once by the supervised subscriber, with explicit job correlation,
bounded metrics, and committed outcomes distinguished from stale work and failed attempts.
The [observability convention](conventions/observability.md) records the full boundary
audit, event catalog, ownership, and delivery limits.

The observability refactor integrated into local `main` centralizes Playback event names for logging and
PromEx, shares metadata/timing mechanics for Movies and Series identification, and
shares Libraries recovery reporting/notification with one distinct-library calculation.
Outcome interpretation remains context-owned; event and metric contracts are preserved.
`MIX_TEST_PARTITION=_obs_refactor mix precommit` passed compilation, formatting,
Credo, and 627 tests with one skipped; the focused checks passed 43 tests.
Coverage includes Playback export, context correlation/privacy and both recovery
operations' partial failures, idle silence and unique notifications. Independent
review found no material issues. The same precommit command passed again after
integration into `main` with 627 tests and one skipped. Published and deployed as
`e5a6fb389dec9232c59f07d69a8d342a553b7f34`; release verification is recorded below.

Episode details use a 16 px breadcrumb and show a decorative calendar icon beside
the original air date. The browser capture checks the breadcrumb size and mobile
overflow.

Optional PromEx collection now exports framework metrics and existing application
observations through a bearer-protected `/metrics` endpoint. Collection is disabled by
default; the base installation needs no monitoring settings or external account.
Separate bridge/host Compose overrides add Grafana Alloy with 60-second scraping and
remote write. Cloud credentials belong to Alloy; Grafana dashboards are source-controlled
in `grafana/dashboards/`, with PromEx dashboards regenerated from the pinned dependency.
The operator imported the five framework dashboards into Grafana Cloud and confirmed they
work. The replacement operational dashboard is now imported through the Grafana API as a project overview:
12 rows cover all six contexts, global Phoenix/LiveView, Ecto and Oban, BEAM, and optional
Docker resources. Each functionality groups outcomes, rolling activity and measured-duration
sample counts with mean/p50/p95 where available. It defaults to 24 hours with collapsed
detail rows; missing data stays distinct from zero. The reproducible generator covers all
65 registered event counters. LiveView adapts the pinned PromEx plugin with fixed view/context
labels and adds parameter/render spans. Ecto gets finer duration buckets and a separate
query-error counter; bounded Playback breakdowns distinguish browser diagnostics, FFmpeg
results and close reasons.

Overview verification: `mix precommit` passed compilation, formatting, Credo, and 630 tests
with one skipped; six focused exporter tests cover callback ownership, bounded labels,
Playback breakdowns, Ecto error-only counting, small-query buckets and private-data exclusion.
Structural checks cover 12 rows, 151 detail/summary panels and all 65 event counters.
Promtool 3.5.0 validated all 431 queries on empty data and checked populated sparse histograms
with a counter reset. Compose checks passed base, bridge, host, optional Docker and missing
credentials; Alloy v1.21.1 validates the Docker config. Local Grafana 12.1.1 imported the
JSON, and headless Chrome opened/closed all 11 detail rows with no browser exceptions or
HTTP query failures against an empty local data source. This establishes layout and
empty-state behavior, not representative deployed data. Independent review found no material
issues. No known source-change blockers remain.

A separate `monitoring.docker.yaml` opt-in adds a privileged native-Linux Alloy/cAdvisor
collector with project/service forwarding filters, metric/label allowlists and an independent
WAL. The app and ordinary metrics collector gain no host mounts. The exporter release is
published and deployed on ARM64, and the Docker collector is active. The Grafana Cloud API
accepted the overview update; read-back verified titles, queries and datasource bindings.
Both application and Docker scrapes report `up=1`; fresh samples cover all five expected
services. LiveView callback metrics and Docker CPU, working-set memory and network counters
are queryable. Block-I/O series have not been observed on this host. Cloud visual rendering,
representative resource accuracy and series budgets remain unverified. See the
[monitoring guide](../deploy/compose/monitoring.md),
[decision 0021](decisions/0021-optional-prometheus-metrics.md), and
[decision 0023](decisions/0023-project-overview-monitoring.md).

An optional Loki override now defines a separate Alloy log collector that discovers only
the labelled Bolognesa application container. PostgreSQL logs, metrics Alloy logs, host
logs, and media files are excluded. Loki credentials and Docker socket access are only
required when this override is selected. Compose validation passed for Loki-only, bridge
with metrics, and host-network selection; the embedded config validates with Alloy
`v1.21.1`. `mix precommit` passes with 623 tests and one skipped. On the opted-in
installation, Alloy reported 208 application log entries read and sent, with zero
retries or drops. The app returned HTTP 200; both Alloy services are running and the
database is healthy. Grafana Explore visibility remains to be confirmed by the operator.
See [decision 0022](decisions/0022-optional-loki-logs.md).

The account and access context is `Bolognesa.Accounts`, including its `AuthenticatedUser` contract for verified callers. A reversible migration renames the former `identity_*` tables, sequences, indexes, and constraints to `accounts_*` while preserving users and sessions. Apply the migration with the matching application release. Authorization is delegated to a domain policy; session entities own issue time and expiry, and persistence stores those supplied times. The trusted release console resolves its complete administrator actor, including locale, through the Accounts facade.

Accounts resource lookups use `fetch_*` names with `{:ok, value}`, `:not_found`, or explicit error tuples. `Accounts.fetch_authenticated_admin/0` and `Release.fetch_authenticated_admin/0` replace `admin_actor/0`; the release console still binds `admin` to the actor or `nil` when setup is open. Authentication preserves its `:invalid_credentials` and `:unauthenticated` failure contracts.

## Recorded verification

- Same-tab recovery release: `mix precommit` passed 638 tests with one skipped;
  all 37 Node tests, synthetic MP4/HLS browser checks and local `make check-screenshots`
  passed. The four incoming commits passed the pinned Gitleaks scan.
  [Application CI](https://github.com/avillen/bolognesa/actions/runs/40005733432) and
  [image CI](https://github.com/avillen/bolognesa/actions/runs/40005733566) succeeded for
  `22853b4eb770fb89e3e01a24c85cceb033c7355a`.
  [Screenshot CI](https://github.com/avillen/bolognesa/actions/runs/40005733481) remained
  in video-tool installation at deployment; the equivalent local checks passed.
  `make deploy-release` deployed verified ARM64 image
  `ghcr.io/avillen/bolognesa@sha256:8d45afc6944b096d73376669f07fe9e18c1a685230e9e1f1fd0e0683107bb41d`.
  Backup `pre-migration-20261023-205217-750.dump` was revalidated with `pg_restore`
  and its previous-image reference; migrations were current. HTTP health, served recovery
  JavaScript, authenticated catalogs, playback coordination and unauthenticated media
  rejection passed. Application/database mounts and database environment matched the
  pre-update fingerprints; all three media sources remain read-only. PostgreSQL is
  healthy and the application has zero restarts/OOM. Target-device playback is pending.

- GitHub Actions Node.js migration: container publishing uses `download-artifact@v7`;
  CI and screenshot checks use `checkout@v5`, `cache@v5` and `setup-node@v5`
  where applicable. Screenshot scripts now run on Node.js 24. All nine distinct
  referenced actions declare the Node.js 24 runtime. Actionlint 1.7.7 passed all
  three workflows; all 37 JavaScript tests passed on Node.js 24.22.1.
  `mix precommit` passed compilation, formatting, Credo and 638 tests with one
  skipped on a full rerun after an initial test failure passed in isolation.
  The next GitHub Actions run must confirm artifact publication and screenshot checks.

- Playback simplification and transcode naming: `mix precommit` passed with 635 tests and
  one skipped; `make check-screenshots` passed locally. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39854169225),
  [container image CI](https://github.com/avillen/bolognesa/actions/runs/39854169319), and
  [README screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39854169265)
  succeeded for `8719a3371567a5c2df6c4377a539872cf36ca54e`. `make deploy-release`
  deployed verified image
  `ghcr.io/avillen/bolognesa@sha256:3be80b7c9d1e1d6e5ad19774a057fb3006a51821e5242db7b0346ce4b900b102`
  on ARM64. Migrations were already current; the update created validated backup
  `pre-migration-20261022-230623-15629.dump`, started the app, and passed HTTP health
  verification. `make deploy-status` confirmed the new image running and PostgreSQL
  healthy.

- Project overview release: local `mix precommit` passed with 630 tests and one skipped;
  `make check-screenshots` and the pinned incoming-commit Gitleaks scan passed.
  [Application CI](https://github.com/avillen/bolognesa/actions/runs/39844634227),
  [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39844634284), and
  [image CI](https://github.com/avillen/bolognesa/actions/runs/39844634228) succeeded for
  `833797dd75b1f0e3620abb09ff20b030f6f10167`. `make deploy-release` deployed verified image
  `ghcr.io/avillen/bolognesa@sha256:2c3bc44c38b84d1d2cc158b62d831156e2bf1f7d2d08790974b19004e48969bd`
  on ARM64. Migrations were current; the update created validated backup
  `pre-migration-20261022-220022-14341.dump` and passed HTTP verification. Authenticated
  Movies/Series/Music reads, all six coordination processes, authorized metrics export,
  and unauthenticated metrics/media rejection passed. Project, mounts, environment,
  accounts, library configuration and manual-correction fingerprints match the prior state.
  The Docker collector configuration was validated on the server and activated separately.
  An explicit target relabel fixes cAdvisor's inherited `integrations/cadvisor` job;
  force recreation applies embedded config changes. The focused Compose regression passes.
  Cloud queries confirm both scrapes up, fresh samples from all five expected services,
  LiveView metrics, and Docker CPU/memory/network data. Block-I/O is absent from observed
  series; this is not a representative capacity or quota measurement.

- Episode detail polish: `mix precommit` passed compilation, formatting, Credo,
  and 627 tests with one skipped; `make check-screenshots` passed. Container image
  workflow run [39832608031](https://github.com/avillen/bolognesa/actions/runs/39832608031)
  succeeded for `39741f03e68cf4cec0b2e7169a58f6ac3c920735`. `make deploy-release`
  deployed verified image
  `ghcr.io/avillen/bolognesa@sha256:a519d8649d96d7e0b4cbadbf13738e6449683d0b3e0e9c3d4d3993fff1d4c036`
  on ARM64. Migrations were already current; the update created backup
  `pre-migration-20261022-203734-20383.dump`, passed HTTP health verification,
  and `make deploy-status` confirmed the app running with PostgreSQL healthy.

- Observability refactor release: local `mix precommit` passed compilation,
  formatting, Credo, and 627 tests with one skipped; `make check-screenshots` passed.
  Container image workflow run [39829089422](https://github.com/avillen/bolognesa/actions/runs/39829089422)
  succeeded for `e5a6fb389dec9232c59f07d69a8d342a553b7f34`. `make deploy-release`
  deployed verified image
  `ghcr.io/avillen/bolognesa@sha256:166be707a6907891ddaed67271e6319ff0cf450c8e57a1f7cbba749fea0f6028`
  on ARM64. Migrations were already current; the update created the database backup
  `pre-migration-20261022-201442-19207.dump`, started the app, and passed HTTP health
  verification. `make deploy-status` confirmed the app is running and PostgreSQL is
  healthy. Detailed authenticated catalog, metrics, mount, and remote-write checks were
  not repeated for this release.

- Optional metrics release: [application CI](https://github.com/avillen/bolognesa/actions/runs/39774002378),
  [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39774002367), and
  [image CI](https://github.com/avillen/bolognesa/actions/runs/39774002374) passed for
  `611c2c5b9b5cf15e0eac2d545de23c3ddeb6e723`. The incoming two commits passed the
  pinned Gitleaks scan. `make deploy-release` deployed verified image
  `ghcr.io/avillen/bolognesa@sha256:f63ef2a1fa435c3bf1eeef502ce71675a08a32bff99e8d8e174f9a3ef8c9a85d`
  on native ARM64. Migrations were already current; the normal update created and
  revalidated `pre-migration-20261022-140106-30806.dump` with its previous-image
  reference. HTTP health, authenticated catalog reads, six coordination processes,
  authorized metrics and unauthenticated metrics/media rejection passed. Mounts,
  existing environment, accounts, library configuration and manual-correction
  fingerprints matched the pre-update values; media binds remain read-only.
  Opted-in Alloy v1.21.1 ran without restarts and confirmed completed Grafana Cloud
  remote writes with zero failed/retried/pending samples. The initial observation
  contained 688 active series; this is a startup snapshot, not a representative
  workload or monthly quota measurement. Grafana dashboard rendering remains unverified.

- Optional PromEx: `MIX_TEST_PARTITION=_promex mix precommit` passed compilation,
  formatting, Credo and 623 tests with one skipped. Focused tests verify default-off
  behavior, bearer authorization and sanitized real exports, including bounded HTTP
  labels. Runtime opt-in and missing-token checks passed. Base and optional Compose
  configuration tests cover bridge/host networking and missing monitoring credentials;
  existing deployment configuration, transport and update regressions passed. Alloy
  v1.21.1 configuration validation and a real local authenticated scrape/remote-write
  smoke check passed using actual PromEx output and a synthetic receiver. All five
  bundled dashboards exported as valid JSON. `make check-screenshots` also passed
  with unchanged captures and synthetic playback/navigation checks. These checks do not establish Grafana
  dashboard rendering, representative deployed workload resource usage or Cloud
  series budgets. The deployment verification above separately confirms remote-write acceptance.

- Cross-context Telemetry: `MIX_TEST_PARTITION=_telemetry_rollout mix precommit` passed
  compilation, formatting, Credo, and 620 tests with one skipped. Capture-handler and
  PostgreSQL regressions cover correlation, privacy before emission, inherited Logger
  metadata, one log per observation, handler restart after ordinary and untrappable
  exits, stale suppression, transaction rollback, retries/exhaustion, partial committed
  recovery, and quiet reads/idle polling. Direct delivery tests cover invalid references,
  source/range failures, truncated reads, and closed/unclassified send failures after
  headers without changing the sent HTTP status. Independent review's inherited-metadata
  finding was reproduced and fixed; scoped re-review found no remaining material issues.
  `git diff --check` and local documentation link checks passed. This rollout is included
  in the deployed optional-metrics release above; representative-workflow observations
  and target-device verification remain pending.

- Playback buffering: local `mix precommit` passed compilation, formatting, Credo, and
  563 tests with one skipped; `node --test assets/test/*.mjs` passed 23 tests. Regressions
  cover initial/seek preparation, missing segments, long copied-video segments, short
  completed playlists, and bounded stall diagnostics. Scan batch tests now explicitly
  allow one second for asynchronous PostgreSQL acknowledgements after repeated failures
  at the implicit 100 ms deadline. The production
  Video.js hook passed synthetic MP4/HLS checks in Chrome 155, including full-file seeks,
  pause/resume, paused seeks, and fullscreen-preserving session replacement. A local
  Docker FFmpeg comparison using synthetic H.264/AC-3 media generated three four-second
  segments in approximately 12.3 seconds with the former pacing and 1.1 seconds with
  the initial burst (including container startup). Synthetic full-video conversion from
  an eight-second offset completed with H.264/yuv420p and AAC output. These checks do not
  establish target-server capacity, real-device playback, or production stall reduction.
  Published [application CI](https://github.com/avillen/bolognesa/actions/runs/39695957237),
  [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39695957197), and
  [image CI](https://github.com/avillen/bolognesa/actions/runs/39695957193) passed for
  `ac63da2507caa37bfd9bb7ac7db8a76d5257db5f`. `make deploy-release` deployed verified
  image `ghcr.io/avillen/bolognesa@sha256:4a7e7c6f3414cb1a4341c9961d922b9ec5fc4dfc35f1ed18509754879be27898`
  on native ARM64. The update created and revalidated `pre-migration-20261022-015508-1965.dump`
  with its matching previous-image reference; migrations were already current. Post-update
  checks verified HTTP 200 health, healthy PostgreSQL, authenticated catalog reads,
  unauthenticated media rejection, all six coordination processes, and the new FFmpeg
  arguments and executable option support. Project, mounts, environment, database
  configuration, accounts, libraries, and manual-correction fingerprints matched the
  pre-update snapshot; all three media mounts remain read-only. Actual playback performance
  on the installation still needs representative media and device testing.

- Series UX: local `mix precommit` passed compilation, formatting, Credo, and 559 tests with one skipped; `node --test assets/test/*.mjs` passed 22 tests. Regressions cover contextual navigation, unavailable episodes, selected-version updates, initial preparation failure/retry, malformed return context, same-season advance, and normalized scroll keys. Independent review's three material findings were reproduced and corrected. Synthetic Chrome player checks passed the opening logo lifecycle, controls, direct/HLS playback, seeking, fullscreen session replacement, and diagnostic delivery. `make screenshots` passed the actual mobile series journey, first-viewport player visibility, playback options, menu Escape/focus and resizing, and many long library names. Published and deployed as `2818faf30df960b520866ae5b7c7470bd1884fe2`. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39667788283), [container image CI](https://github.com/avillen/bolognesa/actions/runs/39667788313), and [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39667788410) passed. `make deploy-release` verified image `ghcr.io/avillen/bolognesa@sha256:6126ab06337c953146fc0ea0a1a37ee2ad9b62dda694e023fc3c05a50f7a0292`, created validated backup `pre-migration-20261021-221806-15664.dump`, found migrations current, and passed HTTP health verification. `make deploy-status` confirmed the app is running and PostgreSQL is healthy. Target iPhone/Safari interaction and real-device resets remain unverified.

- Local playback diagnostics now emit Telemetry events with a supervised structured-log subscriber, precise session-close causes, normalized LiveView/owner exits, failed HLS delivery stages, and bounded browser observations correlated by tab/session. LiveDashboard has bounded playback metrics. Naming, units, privacy, handler lifecycle, and delivery limits are defined in the [observability convention](conventions/observability.md#telemetry). `mix precommit` passed compilation, formatting, Credo, and 550 tests with one skipped; `node --test assets/test/*.mjs` passed 20 tests. Chromium 155 synthetic direct/HLS checks passed playback controls, seek/pause/resume, fullscreen/session replacement, and error diagnostics arriving before fallback. Independent review identified HTTP-origin UUID and error-ordering gaps; both were reproduced and corrected with regression checks. Included in the deployed release described above. Next step: review the instrumented release and reproduce the reported mobile resets. Their initiating cause remains unconfirmed; browser suspension or abrupt termination can lose pending observations.

- Music now has a compact mobile player that opens into an accessible full-screen view, with the Bolognesa cat as its default artwork. `mix precommit` passed with 544 tests and one skipped; `node --test assets/test/*.mjs` passed 16 tests; `make check-screenshots` passed. Published and deployed as `c48456a8d4dec9264a29e63723f47237525639f4`. [Image CI](https://github.com/avillen/bolognesa/actions/runs/39327401192) passed. `make deploy-release` verified image `ghcr.io/avillen/bolognesa@sha256:894f4a0b260729bddfa64da579c5a6319a9aa34ce82eb8a09f3d6a4073bf232`, created a pre-migration database backup, and found migrations current. `make deploy-status` confirmed the app is running and PostgreSQL is healthy. Real-device playback remains unverified.
- Music rows now follow the actual browser audio state with a coral highlight, playing/paused labels, and a reduced-motion-aware equalizer. Circular controls start tracks directly and pause/resume the current audio without replacing it; streamed list patches reconcile the indicator. English and Spanish labels are complete. Local `mix precommit` passed compilation, formatting, Credo, and 544 tests with one skipped; `node --test assets/test/*.mjs` passed 16 tests. Chromium 140 synthetic WAV checks passed row pause/resume, native controls, automatic album advance, and returning to the song list during playback. Desktop/mobile screenshots were refreshed. Published and deployed as `bdfe7f0bb52253846258f329583f5b08b2efe9d8`. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39321128066), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39321127944), and [image CI](https://github.com/avillen/bolognesa/actions/runs/39321127999) passed. `make deploy-release` verified image `ghcr.io/avillen/bolognesa@sha256:22967727cd350116eb9b550bb9bf81dd2b12e4bd84ad3a3aeec3232a20e9a00a`, created a validated pre-migration backup, found migrations current, and passed HTTP health checks. `make deploy-status` confirmed the application is running and PostgreSQL is healthy. Real-device playback remains unverified.

- Video playback shows the Bolognesa cat from the sidebar on a matching coral background until the first frame is available for each selected file, including initial compatible-playback preparation. Later buffering and HLS seek/session replacements do not restore it. The unused Phoenix logo SVG has been removed. Chromium 155 synthetic MP4/HLS checks passed for the correct logo, matching background, initial loading, later buffering, new-file preparation, controls, seeks, pause/resume, fullscreen preservation, and Spanish labels; the opening screenshot was visually inspected. `mix precommit` passed formatting, compilation, Credo, and 544 tests with one skipped. `make check-screenshots` passed unchanged captures and six comparator tests on the final version; one earlier local run differed by 160 pixels with maximum channel delta 3 in the movie mobile capture, and the repeat passed without changes. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39247282488), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39247282456), and [image CI](https://github.com/avillen/bolognesa/actions/runs/39247282527) passed for `3063801ac32a4a89232fa4d7035637f9bd893844`; the incoming commits passed the pinned Gitleaks scan. `make deploy-release` deployed image `ghcr.io/avillen/bolognesa@sha256:986098f66ee358e8281f063f7ab73e62debca56941d198013724bce32b19ade5`, created validated backup `pre-migration-20261019-135201-30254.dump`, found migrations current, and passed HTTP health verification. `make deploy-status` confirmed the app is running and PostgreSQL is healthy. HTTP checks confirmed the coral opening styles and hook are served, the logo bytes match the sidebar cat, and the removed Phoenix SVG returns 404. Next step: review representative playback. Real-media and device compatibility remain unverified.

- Music inspection retries a `.mp3`/`.MP3` file with the explicit MP3 demuxer only when automatic detection reports MPEG and its technical metadata is invalid. Both probes share the existing 30-second budget; source/revision checks, output limits, and transient error contracts remain enforced. Regression coverage checks recovery, content-type/extension restrictions, JPEG rejection, command failures, timeouts, and changes during recovery. `MIX_TEST_PARTITION=_scan_fix_final mix precommit` passed compilation, formatting, Credo, and 544 tests with one skipped; `make check-screenshots` passed unchanged captures and six comparator tests. Independent review found no remaining important issues. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39244082459), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39244082487), and [image CI](https://github.com/avillen/bolognesa/actions/runs/39244082546) passed for `4392f8f514b0fec03e202a0024470ea26741a565`; the incoming commit passed the pinned Gitleaks scan. `make deploy-release` deployed image `ghcr.io/avillen/bolognesa@sha256:8f460f67f16bb079fb41cdc3ac1adb1a42eb7490f472e947419c9307a5e31dbc`, validated backup `pre-migration-20261019-132413-17118.dump`, found migrations current, and passed HTTP health verification. Application/database mounts remained unchanged and media mounts stayed read-only. Targeted reinspection and Music import succeeded for all three affected MP3 files. Two invalid source files were deleted at the operator’s explicit request; normal scans marked them missing. All three libraries then reported zero failed, pending, running, or uninspected available files. Real-media decoding remains unverified.

- Music now uses the existing pinned Video.js 10.1.0 dependency for coral audio controls over native authenticated audio. A LiveView-owned data frame preserves the browser-owned player while refreshing and browsing; existing generation, error, album queue, and cleanup behavior is retained. Search input spacing now aligns its field and submit button. Local `mix precommit` passed compilation, formatting, Credo, and 542 tests with one skipped; the five focused Music LiveView tests and all 14 JavaScript tests passed. Independent review found no important issues. `make check-screenshots` passed with updated Music captures and six comparator tests. Chromium 140 verified the actual Video.js play/pause, keyboard seeking, mute, English/Spanish labels, refresh preservation, album advance/navigation/cleanup, 390 px layout, and search-field/button alignment on desktop and mobile. The vendored module regenerates identically. Commit `0c486c8d8ef2c9a3c38e5e5888d5531674d53e14` is deployed from image `ghcr.io/avillen/bolognesa@sha256:f786015fcf238501c050ccbc8c7e37ca08905104b93640528479f3cf66388ba2`. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39241834434), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39241834579), and [image CI](https://github.com/avillen/bolognesa/actions/runs/39241834555) passed; the incoming commit passed the pinned Gitleaks scan. `make deploy-release` created validated backup `pre-migration-20261019-130740-21851.dump` with its previous-image reference, found no pending migrations, and passed HTTP health verification. `make deploy-status` confirmed the app is running and PostgreSQL is healthy; an HTTP smoke check verified the new audio code and styles are served. Next step: verify representative audio and touch/TV controls; those remain unverified.

- Music presentation now uses a larger library heading, coral active tabs, a search panel, album/artist artwork fallbacks, compact track rows, and a player at the foot of the content. The desktop player stays visible while scrolling; mobile keeps it in normal flow to avoid covering controls. Existing search, import feedback, navigation, and album playback contracts are preserved. Local `mix precommit` passed compilation, formatting, Credo, and 542 tests with one skipped; all 13 JavaScript tests passed. The initial full suite hit two 100 ms discovery-message timeouts; both passed `mix test --failed`, then the full suite passed. Static independent review found no important issues. `make check-screenshots` passed, including six comparator tests, synthetic WAV playback/seek/pause/refresh, album navigation/advance, and 390 px overflow and player-overlap checks. Desktop and mobile captures were visually inspected. Commit `3bc827b0b94151f3a424494f530eb4f445ada3ef` is deployed from image `ghcr.io/avillen/bolognesa@sha256:c6f0e4e237360d729e2a98bd92c0b1eecb04b333723053c91267b8bbf594284a`. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39239676800), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39239676961), and [image CI](https://github.com/avillen/bolognesa/actions/runs/39239676958) passed. The incoming commit passed the pinned Gitleaks scan. `make deploy-release` created validated backup `pre-migration-20261019-124951-24327.dump` with the previous image reference, found no pending migrations, and passed HTTP health verification. `make deploy-status` confirmed the app is running and PostgreSQL is healthy; an HTTP smoke check verified the deployed music styles are served. Real-media and touch/TV behavior remain unverified. Next step: review Music with representative libraries.

- Movies now shares Series' poster grid, search toolbar, panoramic header, typography, and palette through shared media styles. Movie versions use responsive rows with availability, playback, and correction actions. Existing navigation, library scope, and player events are preserved. `MIX_TEST_PARTITION=_movie_design mix precommit` passed compilation, formatting, Credo, and 542 tests with one skipped; 29 focused Movie/Series LiveView tests passed. `make check-screenshots` passed with updated desktop movie/player captures and new 390 px movie captures, including library context, overflow, player entry, and correction navigation checks. Static review found no blockers; an isolated Spanish pagination check also fit at 320 px. Screenshot fixtures now wait for PostgreSQL's final TCP listener and disable animations; six comparator tests verify bounded antialiasing allowances still reject larger changes. Commit `02b1bf44a337cc5dc4c2df0a0fb3f4c0b6bcf78c` is deployed from image `ghcr.io/avillen/bolognesa@sha256:97ade1d6c793ca821bb25529299e529c675c22b07b408f90f16d66d3da0b6972`. [Container image CI](https://github.com/avillen/bolognesa/actions/runs/39179189267) passed validation and native AMD64/ARM64 builds; [application CI](https://github.com/avillen/bolognesa/actions/runs/39179186708) and [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39179186710) passed. The screenshot workflow's only mismatch was 71 antialiased pixels across operating systems in `movie-mobile.png`; the comparator now permits channel difference of 2 for that capture and keeps its other screenshot limits. `make deploy-release` created validated backup `pre-migration-20261019-020906-20025.dump`, found no pending migrations, and passed HTTP health verification. `make deploy-status` confirmed the app is running and PostgreSQL is healthy. Real-media and touch/TV behavior remain unverified; next step: review Movies with representative libraries.

- Series browsing now uses larger poster cards, an integrated search toolbar, a poster/backdrop detail header, full-card season links, and episode rows with stills, summaries, and availability. Styling retains the shared charcoal, warm white, and coral tokens; English and Spanish strings and missing-art fallbacks are preserved. `MIX_TEST_PARTITION=_series_design mix precommit` passed compilation, formatting, Credo, and 542 tests with one skipped; the 10 focused Series LiveView tests also passed. Desktop and 390 px mobile captures were visually inspected; browser checks verified no mobile horizontal overflow and library-preserving catalog/series/season/episode navigation. Static review found no blockers. The final `make check-screenshots` passed, including all six screenshot comparator tests. Commit `8ec699b0cad296ba6d104db13781085ad0039dd0` is deployed from image `ghcr.io/avillen/bolognesa@sha256:4814a2309c5a1d5d451e666f25b12a099150b91f23b3368cae6b8d94e850c96e`. [Container image CI](https://github.com/avillen/bolognesa/actions/runs/39175562972) passed validation and native AMD64/ARM64 builds. `make deploy-release` created validated backup `pre-migration-20261019-011532-6424.dump`, found no pending migrations, and passed HTTP health verification. `make deploy-status` confirmed the app is running and PostgreSQL is healthy. Real-media and touch/TV behavior remain unverified; next step: review Series with representative libraries.

- Video.js 10.1.0 controls are implemented and deployed for movies and episodes. Direct and compatible video share one integrated timeline; compatible seeks display the original file position and restart FFmpeg through the existing server events. Drag previews do not restart conversion, paused seeks remain paused, and the player container survives session changes. `MIX_TEST_PARTITION=_videojs mix precommit` passed compilation, formatting, Credo, and 542 tests with one skipped; 13 JavaScript hook/timeline tests passed. Synthetic MP4/HLS checks passed in Chrome 155, covering actual controls, keyboard and committed drag seeks beyond the generated fragment, global time, pause/resume, fullscreen preservation, paused replacement, and Spanish labels. `make check-screenshots` passed locally with updated movie, episode, and player captures, real synthetic WebM controls through LiveView, and the existing WAV music checks. The vendored module and notices regenerate identically. These browser checks do not establish end-to-end FFmpeg performance or real-media/device compatibility; representative playback on target devices remains the next step.

- Current application release: `5a6e5e7e1d22fd07c1c1371b71e2f09e95801722`. [Application CI](https://github.com/avillen/bolognesa/actions/runs/39172948918) and [image CI](https://github.com/avillen/bolognesa/actions/runs/39172948923) passed. The screenshot workflow's only mismatch was one rounded-frame edge pixel in each of three captures; the comparator now permits one pixel with a channel difference of 16–20 and keeps its other screenshot limits. Local screenshot checks and the six comparator tests passed with that rule. The published commit passed the pinned Gitleaks scan. `make deploy-release` activated image `ghcr.io/avillen/bolognesa@sha256:d400038af02afba41517287c6cda145490d27d847a6b1af81ed87d2bec522f60` on ARM64 and created the validated backup `pre-migration-20261019-003853-17398.dump`. No migrations were pending; PostgreSQL is healthy and the deployment HTTP health check passed. Real-media/device playback remains unverified.

- Playback context naming now distinguishes video source selection and compatible video sessions from music track selection (`start_video` / `start_track`). The use cases are `StartVideoPlayback` and `StartTrackPlayback`, and their repository callbacks are `find_video_source` and `find_track_source`; callers, tests, and backend conventions use the explicit names. `mix format` and the focused video/track playback and transcode controller tests passed (10 tests). The release verification with `MIX_TEST_PARTITION=_release_20261018 mix precommit` passed compilation, formatting, Credo, and 542 tests with one skipped; the six JavaScript hook tests also passed. The isolated run avoids the extra identification jobs previously observed in the shared test database. No API aliases are retained.

- Episode playback now continues to the next available episode of the same series in numeric season/episode order for direct and compatible delivery. Continuation crosses seasons, skips missing versions and all episodes in the completed file, and stops at the final available episode. Playback restarts invalidate pending continuation; obsolete events cannot cancel it. Local `mix precommit` passed compilation, formatting, Credo, and 542 tests with one skipped; `node --test assets/test/*.mjs` passed six hook tests. Coverage includes ordering, multi-episode files, authorization, final/stale events, compatible-session cleanup, and pending-result races. The existing copied-version fixture now records the copied file’s actual modification time. Independent review found no remaining issues. Included in the current deployed release; real media/device playback remains unverified, and browser autoplay restrictions can still require Play. Next step: verify consecutive playback with representative media in a browser and on target devices.

- Movie and episode details automatically load the first available version in the existing version order and attempt autoplay for direct and compatible delivery; manual switching remains available, and no player is prepared when every version is unavailable or no versions are linked. LiveView coverage verifies initial loading, switching, unavailable-version skipping, and the empty player state. Local `mix precommit` passed compilation, formatting, Credo, and 535 tests with one skipped; the focused movie and episode screen checks passed 21 tests, including initial compatible autoplay, and `node --test assets/test/*.mjs` passed five hook tests. Included in the current deployed release; real-media playback remains unverified. Browser autoplay restrictions may still require pressing Play. Next step: verify movie and episode entry and autoplay with representative media in a browser.

- Automatic video fallback: movie and episode browser failures now start compatible H.264/AAC playback at the reported position without a manual mode button. Duplicate and stale errors are ignored, and failures remain visible without automatic retries. Playback presentation transitions are shared by movie and episode screens through `PlaybackState`; `PlaybackControl` owns preparation and session startup/cleanup, while `SelectVersion` validates selection. Movie playback coverage is split into independent scenarios. Local `mix precommit` passed compilation, formatting, Credo, and 529 tests with one skipped; `node --test assets/test/*.mjs` passed five hook tests. LiveView coverage verifies fallback, position retention, stale/duplicate events, session replacement, pause/resume, seeking, and terminal failures; independent review found no issues. Included in the current deployed release; real video decoding remains unverified. Next step: verify the automatic transition with representative media in a browser and on the target devices.

- Series convention fixes: review pages load episode associations in one batch, with a query-count regression preserving selection order. Individual series, episode, review-item and provider-season facade lookups use `fetch_*` and distinguish `:not_found` from failures; use cases, exclusive DTO paths, ports, adapters and UI callers follow the revised contracts. All four Series adapter types use `module()`, and the writer uses one spec for its default argument. Local `mix precommit` passed compilation, formatting, Credo, and 522 tests with one skipped; independent review found no issues. No known blockers remain for these fixes. Included in the current deployed release.

- Movies and Series now use `Bolognesa.Infrastructure.Providers.TmdbClient` for the identical bounded HTTP transport, with a neutral error type. Provider ports, endpoints, payload mappers, and behavior remain context-owned. Existing focused provider coverage passed before extraction (10 tests); local `mix precommit` passed after extraction with compilation, formatting, Credo, and 521 tests passed, one skipped. Included in the current deployed release.

- Direct durable jobs: local `MIX_TEST_PARTITION=_direct_jobs mix precommit` passed compilation, Credo, and 521 tests with one skipped. All three disposable upgrade verifiers passed empty/seeded migrations, stable catalog/account/manual-association snapshots, migrated-worker execution, deleted-before-start recovery, refused reversal, and atomic rollback of earlier batches on inconsistent active request links. Coverage includes requests without matching events and existing same-token Music imports with invalid jobs/revisions; combined checks carry original-schema inspection/Music backlogs through the video upgrade. Real PostgreSQL notifications verify that supported Oban insertion wakes the queues. The historical content-context verifier passed two pinned rebuilds. Independent review's active-request validation finding was reproduced and fixed; no runtime correctness findings remained. Included in the deployed release described below.

- Libraries convention review: scan status lookups use `fetch_status` / `fetch_scan_status`; inspection lookup and count APIs use `fetch` / `fetch_inspection_counts` across facades, use cases, ports, adapters, and callers. Adapter aliases consistently use `module()`. `mix format` and `git diff --check` passed; tests and `mix precommit` passed as part of the direct jobs verification. Included in the deployed release described below.

- Accounts lookup convention and `Actor` to `AuthenticatedUser` rename: local `mix precommit` passed compilation, Credo, and 522 tests with one skipped. Lookup coverage verifies success, absence, and administrator persistence-error propagation; existing checks verify authentication, credential-log privacy, and release-console actor/locale binding. Included in the deployed release described below. Other contexts retain their existing lookup contracts.
- Context convention review: local `mix precommit` passed with 519 tests and one skipped, compilation, and Credo. PostgreSQL regressions verify Movies/Series recovery reports failed writes while preserving other successful recoveries. Matching/retry policies are domain-owned; Music maps inspection tags into its own model; Playback uses explicit error contracts and structured logging. Account/session SQL operations suppress credential hashes, and a fresh-VM regression covers persisted role mapping before domain modules load. Detail reads reject more than 100 versions or seasons with translated UI feedback instead of truncating. An independent code review's UI-feedback finding was corrected and verified. Included in the deployed release described below.
- Current `make check-screenshots` passed with unchanged captures and synthetic WAV playback/navigation checks in Chromium 140. Its first run exposed the Accounts role mapper's dependency on an already-loaded atom; explicit allowlisted role mapping fixed that cold-start failure. The Accounts migration verifier passed empty/seeded upgrades, rollback, and reapplication against a disposable database.
- Libraries convention fixes: local `mix precommit` passed with 505 tests and one skipped, compilation, and Credo. Focused Libraries checks passed with 171 tests and one skipped. Regression coverage verifies private source registration does not enter SQL logs, scan recovery handles at most 100 candidates per pass, and waiting retries or unexpired attempts do not block eligible recovery. Inspection retry limits are domain-owned; application port types and Elixir layout/control flow were corrected. An initial full run hit an existing interface-language test's 100 ms async timeout; `mix test --failed` and the subsequent full `mix precommit` passed. Included in the deployed release described below.
- Accounts convention fixes: local `mix precommit` passed with 502 tests and one skipped, compilation, and Credo. Regression coverage verifies the password-hasher result contract, release-console locale preservation, domain session lifetime across calendar boundaries, and persistence of independently supplied issue/expiry times. Included in the deployed release described below.
- Accounts rename: local `mix precommit` passed with 499 tests and one skipped, compilation, and Credo. `MIX_ENV=test mix run --no-start scripts/verify_accounts_migration.exs` verified empty and seeded upgrades, rollback, and reapplication in a disposable database. Included in the deployed release described below.
- Content-context local `mix precommit`: 499 tests passed, one skipped; compilation and Credo passed. Coverage includes foreign-type mutation rejection, bounded owner backfill/dispatch/recovery, atomic inventory/request/event and work/association rollback, manual/stale revision races, and equal-ID direct/HLS delivery. A fresh whole-change review found an HLS query-parameter route ambiguity; regression tests reproduced it for both manifests and segments, and the corrected controller uses path parameters exclusively.
- The fixed disposable content-context migration verifier passed two full fresh/reset rebuilds, independent sequence checks, legacy table/function removal, and refused reversal. Both historical migration verifiers passed their seeded and empty cases without requiring obsolete application workers or writers.
- `make check-screenshots` passed with unchanged captures, including synthetic PCM WAV playback, seek/pause, album advance, previous/next, music navigation continuity, and stopping on exit in Chromium 140. Three audio-hook tests and five screenshot-comparator tests passed. These checks do not establish real-device or other-format decoding.
- Music checks cover metadata, current-token/revision validation, concurrent imports, outbox atomicity and recovery, authorized retries, literal searches, stale UI responses, bounded queues, and authenticated MIME/range delivery. Synthetic controller bytes establish delivery rather than decoding.
- Published [application CI](https://github.com/avillen/bolognesa/actions/runs/39063824027), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/39063823867), and [image CI](https://github.com/avillen/bolognesa/actions/runs/39063824181) passed for `c743270a1d1467592e6ebcae3ae85ffdb678b79c`. The scanned commits passed the pinned Gitleaks scan with no findings.
- Deployed that commit with `make deploy-release` using verified image `ghcr.io/avillen/bolognesa@sha256:1f06c075a6662d7ebb7c2beb817eff8702c126c331198171957dc252ac0ef280` on ARM64 (`aarch64-unknown-linux-gnu`). The normal update created and validated `pre-migration-20261017-214853-20660.dump` with its previous-image reference (`ghcr.io/avillen/bolognesa@sha256:5cfcfcb15197077ee58bd2af8fbd32b66a8e41bf7b42b7dca08d0abfe7f618b0`), applied the three direct-job migrations, dropped all four obsolete event tables, and passed HTTP health checks. Post-deployment backup validation confirmed the non-empty dump and previous image reference.
- Post-deployment checks verified all three direct-job migrations applied, absence of legacy event tables and dispatchers, all six coordination processes (`ScanReconciler`, `InspectionReconciler`, Movie `IdentificationReconciler`, Series `IdentificationReconciler`, Music `ImportReconciler`, `TranscodeManager`), Oban supervisor execution, healthy PostgreSQL, HTTP 200 health, authorized catalog reads for movies, series, and music, and HTTP 401 for unauthenticated movie, episode, and music delivery. Application/database mounts and database configuration matched their pre-update fingerprints; all three source mounts remain read-only.
- Published [application CI](https://github.com/avillen/bolognesa/actions/runs/38989153003), [screenshot CI](https://github.com/avillen/bolognesa/actions/runs/38989153098), and [image CI](https://github.com/avillen/bolognesa/actions/runs/38989153069) passed for `655ea5908fb5f7812869029638ce9c7012f5522f`. The incoming three commits passed the pinned Gitleaks scan with no findings.
- Deployed that commit with `make deploy-release` using verified image `ghcr.io/avillen/bolognesa@sha256:5cfcfcb15197077ee58bd2af8fbd32b66a8e41bf7b42b7dca08d0abfe7f618b0` on ARM64. The normal update created and validated `pre-migration-20261017-030608-15187.dump` with its previous-image reference, then applied the reversible Accounts rename and passed HTTP health checks. The backup was revalidated after activation. No database reset was performed in this update; this backup does not replace the earlier pre-reset backup associated with the content-context rebuild.
- Post-deployment checks verified the Accounts table rename, all ten recovery/dispatch/playback coordination processes, healthy PostgreSQL, HTTP 200 health, and HTTP 401 for unauthenticated movie, episode, and music delivery. Normalized application/database mounts and database configuration matched their pre-update fingerprints; all three source mounts remain read-only. Setup remains open with no administrator configured. Authenticated browsing and real-media playback on this installation remain unverified.
- Local Compose startup, migrations, and initial setup were verified on x86_64. A compatible MP4 played in Chrome on a private deployment. Music inspection handles attached cover art without rejecting valid audio.

## Limits and next work

iPadOS 16.2 reportedly leaves all catalogs loading in both Safari and Chrome.
The eagerly imported Video.js bundle contains class static initialization blocks,
unsupported by Safari before 16.4; a parse failure prevents LiveView from starting.
The application build now targets Safari 16.2 alongside ES2022, lowering these blocks.
A regression fails with the previous target and passes with the corrected target;
the actual `mix assets.build` output also contains no class static blocks.
Local `mix precommit` passed compilation, formatting, Credo and 638 tests with one
skipped; Node checks passed 42 tests. The production-hook harness now uses the
application target and passed direct/HLS controls and recovery in Chrome 155.
The default Playwright Chromium run timed out waiting for synthetic MP4 playback;
the documented H.264-capable Chrome run passed. Local `make check-screenshots` passed
with unchanged captures. The correction is published and deployed as
`4c9ba04c337c04db6604d1841e3d8fa0918f589e`, using image
`ghcr.io/avillen/bolognesa@sha256:b436d827020b8f73b3a25fe97ab06d305398c52c82503ad62fef1ef94b2177c4`.
[Application CI](https://github.com/avillen/bolognesa/actions/runs/40223237030) and
[image CI](https://github.com/avillen/bolognesa/actions/runs/40223236863) passed;
[screenshot CI](https://github.com/avillen/bolognesa/actions/runs/40223236784) is pending.
The incoming commit passed the pinned Gitleaks scan. The normal update created and
validated `pre-migration-20261025-195454-10052.dump` and its matching previous-image
reference; no migrations were pending. Post-update checks confirmed the selected
ARM64 image, healthy PostgreSQL, HTTP 200, authenticated catalog reads, unchanged
application/database mounts and configuration, three read-only media mounts, and
HTTP 401 for unauthenticated media delivery. The served JavaScript contains no class
static blocks. Next: verify catalog connection and representative playback on the
target iPad; device compatibility remains unverified.

The reported Hisense built-in browser still shows play/pause, volume, settings and
fullscreen but no timeline or time labels after the deployed Intl unit-format fallback.
The device failure remains unresolved; the operator confirmed the timeline is still absent
after the additional Unicode formatter patch was deployed. The browser's engine/version and API support have
not been measured; the previous formatter simulation did not establish TV compatibility.

A further formatter dependency on Unicode property escapes was reproduced locally:
simulating their absence raises three browser errors and leaves time labels empty, but
still renders a slider, so this does not reproduce the entire TV symptom. The vendoring
adapter now removes the localized padded minute zero with string operations instead.
The expanded production-hook Chrome 155 check passes with both Intl unit formatting and
Unicode property escapes disabled, including English/Spanish labels and direct/HLS seeks.
Disabling CSS container queries alone did not reproduce the missing timeline.
`mix precommit` passed compilation, formatting, Credo and 638 tests with one skipped;
`node --test assets/test/*.mjs` passed 37 tests. Independent review found no blocking
issues in the additional formatter patch.
The additional formatter changes are published and deployed as
`b464f27bbb10326b060ad4ad89ee9f55d8dbd090` with image
`ghcr.io/avillen/bolognesa@sha256:4762198f4c8c34d5eecca85cb1caf47a93c160b8fd11a03b68219a9a615009f7`.
[Application CI](https://github.com/avillen/bolognesa/actions/runs/40008842220) and
[image CI](https://github.com/avillen/bolognesa/actions/runs/40008842125) passed.
Local `make check-screenshots` passed with unchanged captures;
[screenshot CI](https://github.com/avillen/bolognesa/actions/runs/40008842076) also passed.
The incoming commit passed the pinned Gitleaks scan.
The normal update created and validated `pre-migration-20261023-211030-29525.dump`
and its previous-image reference; no migrations were pending. Post-update verification
confirmed the selected image running, healthy PostgreSQL, successful HTTP health,
unchanged application/database mounts and all three media mounts remaining read-only.
The backup was revalidated after activation. The operator subsequently confirmed that
the timeline remains absent on the TV.
An automatic `controls` observation is implemented to measure the actual packaged
skin once after playback starts: group/slider/track dimensions, label count, hidden
ancestor styles and bounded browser capabilities. Raw user-agent text and time labels
are not transmitted. The observations use existing file/session authorization and
budgets. This instrumentation does not change or claim to fix the timeline.
Local `mix precommit` passed compilation, formatting, Credo and 638 tests with one
skipped; Node checks passed 39 tests. The production-hook Chrome 155 checks passed
with the measured dimensions, labels and simulated unsupported APIs. Focused server
and logging checks passed seven tests; independent review found no blocking issues.
The observation is published and deployed as `93b32fc40b26a23d2759dfac510740f5ba8e93d2`,
using image `ghcr.io/avillen/bolognesa@sha256:a3357d2467d3fc0970f042dd6d772f471e0c7af7826d58d446fe752b3f45150d`.
[Application CI](https://github.com/avillen/bolognesa/actions/runs/40010978786),
[screenshot CI](https://github.com/avillen/bolognesa/actions/runs/40010978723) and
[image CI](https://github.com/avillen/bolognesa/actions/runs/40010978867) passed.
Local `make check-screenshots` passed with unchanged captures, and the incoming commit
passed the pinned Gitleaks scan. The update created and validated
`pre-migration-20261023-212653-22060.dump` and its previous-image reference;
no migrations were pending. Post-update verification confirmed HTTP 200, healthy
PostgreSQL, unchanged application/database mounts and three read-only media mounts;
the backup and matching previous-image reference were revalidated.
The target-TV observation reports that the time group and slider have width but their
track and labels are absent. CSS container/layer checks and Unicode properties succeed,
`intl_units` is false, `intl_lists` is true, and the browser reports Chrome major 111.

The number-format fallback previously handled only `RangeError`. A simulated
`TypeError` from `Intl.NumberFormat` with unit style reproduces the empty labels and
missing track; accepting that error only for unit formatting restores the controls in
the production-hook browser check. Native unit-list formatting is retained in the
regression to match the TV probe. Unrelated formatting errors continue to surface.

Local `mix precommit` passed compilation, formatting, Credo and 638 tests with one
skipped. Node checks passed 41 tests, the production-hook check passed in Chromium 155,
and `make check-screenshots` passed with unchanged captures. The additional TypeError
fallback is published and deployed as `c9458fac84b7714eb9aedf60b015baacd85b949f` with
image `ghcr.io/avillen/bolognesa@sha256:fab4c64ed73aa597bb33177936cf5750a211a6330373f0b75afad81b5d5107d2`.
[Application CI](https://github.com/avillen/bolognesa/actions/runs/40222308350) and
[image CI](https://github.com/avillen/bolognesa/actions/runs/40222308361) passed. Local
screenshots passed unchanged and Gitleaks found no leaks in the incoming commit. The
update created and validated `pre-migration-20261025-194256-21604.dump` with the previous
image reference. Post-update checks confirmed HTTP 200, healthy PostgreSQL, unchanged
application/database mounts and three read-only media mounts; the backup was revalidated.
The TV's exact Intl exception type and corrected rendering still need confirmation.

Optional PromEx/Alloy is published and verified on an opted-in ARM64 installation,
including accepted Grafana Cloud remote writes. The operator confirmed the Explore query
and five imported PromEx dashboards work. The replacement project overview is imported and verified through the Grafana Cloud API;
its exporter release and optional Docker collector are deployed. Next step: inspect Cloud
rendering and measure series/resource use during representative workflows; block-I/O data
has not been observed on this host.
Ordinary installations can continue without monitoring infrastructure.

The cross-context Telemetry rollout is published and deployed. Observations are best
effort and do not replace durable job state; LiveDashboard is not a historical metrics
store. Representative scan, identification, import and playback diagnostics still need
verification during real use.

The library repository query import follows the module-level convention, and the Music refresh worker defines its policy alias before the Oban macro that uses it. `MIX_TEST_PARTITION=_review_import_scope mix precommit` passed compilation, formatting, Credo, and 521 tests with one skipped. The initial default-database run failed an inspection recovery assertion that counted six completed jobs instead of two; the isolated run passed. The source of the extra jobs in the default database remains unconfirmed.

The direct-job refactor is implemented, reviewed, published, and deployed. Representative-backlog maintenance duration remains unmeasured.

The [content-context change](decisions/0019-content-context-boundaries.md) is implemented, reviewed, published, and deployed. The agreed whole-database rebuild removed accounts, library configuration, corrections, imported catalog data, and Oban jobs while preserving original media mounts. Post-deployment verification now confirms an administrator and successful authenticated catalog reads. Any sources registered after the rebuild must retain their existing internal paths. The [deployment guide](../deploy/compose/README.md#one-time-content-context-rebuild) documents the rebuild and backup/restore contract.

Native ARM64 startup and basic HTTP behavior are now verified; mobile/TV playback, manual keyboard/touch interaction, other audio format decoding, and performance across real media remain unverified. The reported series inspection failure was traced on the deployment to an empty source file; the operator explicitly requested its deletion, and a subsequent successful scan marked it absent.

Playback progress is not persisted across sessions. Multi-episode files play in full from the beginning. Music has no conversion, queue editing, saved progress, or playback across other screens. The next music outcome is queue editing or continuous playback across authenticated navigation; acceptance outcomes are in the [roadmap](roadmap.md). The generic HTTP deployment is for trusted private networks and must not be exposed directly to the Internet.

The project uses MIT licensing. A recorded full-history Gitleaks scan found no unallowlisted findings after public-history cleanup; CI scans incoming commits. A final public-release privacy review remains necessary because secret scanning does not detect every private detail.

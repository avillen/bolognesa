# Project status

Last reviewed: 2026-10-28.

## Available

Movies, series, and local music support scanning, inspection, browsing, and playback. Movies/series use TMDb with manual corrections. Music supports ordered album playback. One administrator manages the installation; original media stays read-only.

Video has best-effort same-tab position/pause recovery, not durable account progress. Music stops when leaving its screen or reloading. Numbered episode parts are implemented and locally tested but not deployed. See the [README](../README.md) for use and [changelog](../CHANGELOG.md) for release/upgrade notes.

## Verification

- **Application:** this checkout passed `MIX_TEST_PARTITION=_release_docs mix precommit`: compilation, formatting, Credo, 653 tests passed, one skipped. All 43 Node tests passed on Node 22.20.0. These tests do not establish real-media decoding.
- **Local installation:** Docker 29.5.2 / Compose 5.0.0 on x86_64, with emulated ARM64 PostgreSQL. Chrome 156 passed administrator setup, sign-in, library registration, and an empty scan. Data survived down/up; media was read-only. First boot needed the documented PostgreSQL initialization retry.
- **Server workflow:** a freshly built HTTP image passed isolated Docker install, backup, update, and restore with synthetic data and read-only media. Compose configuration/update/transport checks also passed. This was local testing, not a new server deployment.
- **Earlier browser checks:** generated MP4/HLS controls and same-tab recovery passed in Chrome/Chromium 155; generated WAV controls passed in Chromium 140. Earlier screenshot checks passed and were not repeated for these documentation edits.
- **Deployment observations:** earlier native Linux ARM64 checks verified startup, migrations, authenticated catalogs, and media authorization. A compatible MP4 played in Chrome on a private deployment. Capacity remains unmeasured.
- **Actual devices:** an operator reported the app working on iPadOS 16.2 after the build fix, without recording browser/media details. A Hisense browser displayed the timeline and times after the formatter fix. Broader device playback is unverified.

Same-tab recovery and the iPad/Hisense fixes are deployed; later probe cleanup is not. The full player harness currently fails at a control click in Chrome 156 and MP4 startup in pinned Playwright Chromium. Real iPhone recovery and the cause of reported page recreations remain unverified.

## Remaining work

- Follow the [HLS plan](design/hls-playback-optimization-plan.md): the synthetic baseline reproduced repeated manifests while paused and terminal failure after expiry. Next are pause/expiry regressions, target-server measurements, and native-HLS checks.
- Optional [monitoring](../deploy/compose/monitoring.md) delivers metrics on ARM64; representative resource budgets and replacement-overview rendering remain unverified. Docker block-I/O was not observed; Loki Explore visibility is unconfirmed.
- Optional [media automation](../deploy/compose/media-automation.md) passed panel/connection, persistence, and hardlink checks on ARM64. End-to-end import/seeding/playback remains unverified.

## Release preparation

Issue #11 simplifies user documentation and adds a changelog without changing functionality. Local links/anchors and the independent documentation review passed. Release-specific notes belong in the changelog; the README describes everyday use. Next: the remaining preview checks, including the public-release privacy review.

The LAN/HTTP profile must not be exposed directly to the public Internet. Database compatibility during 0.x is not guaranteed; backup and recovery instructions are in the [deployment guide](../deploy/compose/README.md#backup-update-and-recovery). Large-backlog migration time remains unmeasured. A final public-release privacy review is still needed; the milestone is not declared complete.

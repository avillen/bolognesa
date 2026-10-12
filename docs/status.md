# Project status

Last reviewed: 2026-10-12.

Bolognesa is an early self-hosted media center built with Phoenix LiveView, Ecto, PostgreSQL, and Oban. The repository includes local Docker Compose development and a generic Linux Compose deployment. Movie and series libraries, scanning, technical inspection, TMDb identification, catalog browsing, authorized direct playback, and an optional FFmpeg/HLS path are implemented.

## Verification and limits

- Local Docker Compose startup, database migrations, and the first setup page have been verified on an x86_64 host. This does not verify native ARM64 behavior.
- `mix precommit` and the project test suite have passed in recent local runs. CI configuration is present; its latest GitHub run should be checked before relying on it for a release.
- A compatible MP4 has played in Chrome on the private deployment. Playback controls, mobile and TV playback, and performance across media formats still need hands-on verification.
- Scanning discovers files; identification is a separate step. Automatic metadata lookup requires a TMDb read token.
- Playback progress is not persisted across sessions. Multi-episode files play in full from the beginning.
- The generic HTTP deployment is intended for a trusted private network and must not be exposed directly to the Internet.

## Before the first public release

The repository now uses the MIT License. The history on `main` has been rewritten to remove old operational notes, private deployment files, local and NAS paths, internal addresses, and personal commit email addresses. A full-history Gitleaks scan reports no unallowlisted findings; `.gitleaksignore` records two exact matches for fixed development/test signing keys, which are not used in production. CI scans incoming commits for known credential patterns, but it does not replace a review for personal paths, addresses, or operational details.

The public-facing README and contributor guide describe local setup. The README includes a selected screenshot gallery and a foldable gallery of all 15 user-facing screens, generated from synthetic sample content. `make screenshots` rebuilds the images with an isolated database and browser-generated video; CI checks that committed captures stay current. No personal media files or paths are included. See the [roadmap](roadmap.md) for open product work and [decisions](decisions/README.md) for architectural context.

# Changelog

Release notes and upgrade information. See the [README](README.md) for setup and playback limits.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Allow up to thirty seconds to prepare compatible video playback, while starting as soon as output is ready.

### Added

- Numeric FFmpeg preparation diagnostics and a Grafana row for startup timings and progress.

## [0.2.0] - 2026-11-08

Better music listening.

### Added

- Keep music playing while browsing, with a persistent player and an editable queue.
- Revisit recently played albums, continue from the last heard track, or replay from the beginning.
- Track listening dates and use system media controls where supported.
- Search as you type.

### Changed

- Improve video compatibility, avoid unnecessary conversion, and preserve the player across episode changes.
- Simplify library management.

### Limitations

Music playback and queues last only within the current tab and do not survive a full reload. System controls depend on browser support.

Video compatibility remains experimental. Conversion supports one shared session, without HDR tone mapping. Video progress is not saved to accounts or shared across devices. Physical iPhone, Bluetooth, and ARM64 NAS playback need further testing.

### Upgrading

Includes database migrations for listening activity. Before updating, keep a validated database backup, its matching application image, and private configuration. Compatibility between 0.x releases is not guaranteed; an older image does not undo migrations. Existing video files may need a fresh inspection for compatibility selection; see the [playback guide](docs/playback.md).

## [0.1.0] - 2026-10-29

First experimental preview for private home use.

### Added

- One administrator account and movie, series, and music libraries.
- Recoverable scanning and inspection, TMDb identification, and manual corrections.
- Movie/episode playback, file versions, episode continuation, and numbered episode parts.
- Limited FFmpeg/HLS video conversion and best-effort same-tab position/pause recovery.
- Local tracks, artists, albums, and ordered album playback.
- Local Docker setup and a private Linux server profile with backup/restore tools.
- Public Linux AMD64/ARM64 images at `ghcr.io/avillen/bolognesa:v0.1.0`, with the immutable digest recorded in the release notes, and a source-build alternative from tag `v0.1.0`.

### Limitations

Playback depends on the browser, container, codecs, and hardware. Video recovery is temporary and does not provide saved account progress or cross-device resume. Music stops when leaving its screen or reloading. The LAN/HTTP deployment must not be exposed directly to the public Internet.

### Upgrading

Database compatibility is not guaranteed during 0.x development. Before updating, keep a validated backup and its matching application image. Follow the [backup and recovery guide](deploy/compose/README.md#backup-update-and-recovery).

[Unreleased]: https://github.com/avillen/bolognesa/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/avillen/bolognesa/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/avillen/bolognesa/releases/tag/v0.1.0

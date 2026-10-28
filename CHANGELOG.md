# Changelog

Release notes and upgrade information. See the [README](README.md) for setup and [status](docs/status.md) for verification limits.

## 0.1.0 — Unreleased

First experimental preview for private home use.

### Included

- One administrator account and movie, series, and music libraries.
- Recoverable scanning and inspection, TMDb identification, and manual corrections.
- Movie/episode playback, file versions, episode continuation, and numbered episode parts.
- Limited FFmpeg/HLS video conversion and best-effort same-tab position/pause recovery.
- Local tracks, artists, albums, and ordered album playback.
- Local Docker setup and a private Linux server profile with backup/restore tools.

### Limits

Playback depends on the browser, container, codecs, and hardware. Video recovery is temporary and does not provide saved account progress or cross-device resume. Music stops when leaving its screen or reloading. The LAN/HTTP deployment must not be exposed directly to the public Internet.

### Updates

Database compatibility is not guaranteed during 0.x development. Before updating, keep a validated backup and its matching application image. Follow the [backup and recovery guide](deploy/compose/README.md#backup-update-and-recovery).

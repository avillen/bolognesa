# Product

Bolognesa is a self-hosted media center for home use, built with Elixir and Phoenix. It began as a personal learning project and is developed in public.

## Scope

The v0.1.0 experimental preview lets one administrator add media folders, scan files, identify movies and series with TMDb, correct matches, and play compatible files. Local music supports tracks, artists, albums, and ordered album playback. Original files are read-only.

Video has temporary same-tab recovery, not durable account progress or cross-device resume. Music playback stays within the music screen. More accounts, playlists, general remote access, and dedicated clients remain future possibilities.

The LAN/HTTP deployment must not be exposed directly to the public Internet. Database compatibility across 0.x releases is not guaranteed; keep backups before updating.

## Principles

- Keep setup and the application understandable.
- Stay practical on modest hardware.
- Make background work recoverable and failures clear.
- Preserve manual corrections.
- Describe verified behavior separately from expectations.

People are welcome to try the project, report reproducible problems, and contribute focused improvements. Discuss substantial features first; the maintainer sets priorities and cannot promise support for every use case.

See the [status](status.md), [roadmap](roadmap.md), and [architecture decisions](decisions/README.md).

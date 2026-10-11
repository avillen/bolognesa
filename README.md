# Boloñesa

Boloñesa is a self-hosted media center built with Elixir, Phoenix and LiveView. It is named after my cat, and it started as a fun way to explore Elixir by building something I use at home.

This is an early, personal project and a place to learn in public. The goal is a working end-to-end experience that is easy to run and understand, not a production-ready Jellyfin replacement. Simplicity, performance and responsiveness on modest hardware guide the work. Contributions of all sizes are welcome, from experiments with OTP to a small UI fix.

## What works today

- Create the first administrator account and sign in.
- Register movie and series folders, scan them, and inspect discovered video files.
- Identify movies and series with TMDb, review matches, and browse the catalog.
- Open movie and episode pages and choose an available file version.
- Play directly when the browser supports the file's container and codecs. The server streams bounded byte ranges, so browser seeking does not load the whole file into memory.
- Use the existing optional HLS/FFmpeg compatibility path for some unsupported combinations.

## Current limits

Boloñesa is still changing quickly and has only been used as a personal project. Browser and codec compatibility varies; a file in the library is not guaranteed to play. The private QNAP validation recorded one MP4 playing in Chrome, but pause and seeking on the private route, mobile playback and the Hisense TV have not been fully verified. Playback progress is not saved after the player session. Transcoding exists for some cases, but performance depends on the hardware and format.

Scanning discovers files; it does not by itself create catalog movies. Movie and series identification uses TMDb. The application starts without a TMDb token, but automatic identification and metadata lookup need one. A token is optional for startup and can be supplied locally through `.env`.

There is no demo media bundled with the repository. Use a video you have the right to play. For a public demo, choose a file whose license explicitly permits redistribution and display, and include its attribution and license terms.

## Screenshots and demo

Screenshots should come from a real running Boloñesa instance. The most useful screens for an introduction are:

1. Home or the movie library.
2. A movie detail page with an available version.
3. The video player after playback starts.

To record the flow, start the app, sign in, register and scan a mounted media folder, identify one movie, open its detail page, start playback, pause, and seek. Keep personal filenames and paths out of public captures. No screenshots are included yet.

## Quick start with Docker

Requirements: Docker with the Compose plugin and a compatible video file for playback. The first build downloads dependencies and may take a few minutes.

```sh
mkdir -p media
# Copy a video you can use into ./media
docker compose up --build
```

The app is available at [http://localhost:4000](http://localhost:4000). The first visit opens `/setup`; create the administrator account, then sign in. Compose starts PostgreSQL, waits for it to become healthy, runs database migrations and starts the app. The local database is stored in a named Docker volume.

In Boloñesa, open **Libraries**, add a movie library with the path `/media`, and start a scan. If `TMDB_READ_TOKEN` is configured, discovered files can be identified and then appear in the movie catalog. Identification runs in the background, so allow it to finish before opening the movie. The `/media` mount is read-only inside the app container.

To configure a different host folder or port, copy `.env.example` to `.env` and edit it:

```sh
cp .env.example .env
```

Set `MEDIA_PATH` to a folder on your machine and `BOLOGNESA_PORT` to an available port. If you want movie identification, add your TMDb API read access token as `TMDB_READ_TOKEN`. Keep `.env` private; it is ignored by Git. These are local development defaults and the web port is bound to `127.0.0.1`.

Stop the services with `docker compose down`. This keeps the database volume. Removing that volume deletes the local Boloñesa database and account.

## Run from source

For native development, install Elixir 1.17 or newer in the supported 1.x series, Erlang/OTP, PostgreSQL, and `ffprobe` (and `ffmpeg` if you want to work on the compatibility playback path). Configure PostgreSQL to match `config/dev.exs`, then run:

```sh
mix setup
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000). The default development media root is a temporary directory; set `BOLOGNESA_LIBRARY_ROOTS` to a colon-separated list of directories when starting Mix if you need different roots. Set `TMDB_READ_TOKEN` in the environment to enable identification and metadata lookup.

Run the tests with PostgreSQL available:

```sh
mix test
```

The project's full local quality check is:

```sh
mix precommit
```

## Contributing

Small, understandable changes are easiest to review and learn from. Bug fixes, performance improvements, refactors, experiments and UI details are all welcome. Please keep simplicity and responsiveness on modest hardware in mind. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and contribution notes.

There is no license file yet. Please check with the maintainer before redistributing or building on this code until a license is chosen.

## Project notes

- [Product and scope](docs/product.md)
- [Current status and verification](docs/status.md)
- [Roadmap](docs/roadmap.md)
- [Architecture and project conventions](docs/conventions/)
- [QNAP deployment guide](deploy/qnap/README.md)

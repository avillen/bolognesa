# Contributing to Boloñesa

Boloñesa is a personal learning project. The most useful contributions make its existing setup, scanning, identification, and playback easier and more reliable.

## Get started

Follow the [Docker quick start](README.md#try-it-with-docker) or [native setup below](#native-development). PostgreSQL is required for tests:

```sh
mix precommit
```

Before updating an existing database, read the [upgrade guidance](README.md#before-updating). The local Compose setup uses development credentials; the separate [server profile](deploy/compose/README.md) is for private networks and must not be exposed directly to the public Internet.

## Native development

Use the CI/Docker versions: Elixir 1.20.3, Erlang/OTP 28.3.3, PostgreSQL 17, and `ffprobe`. The project permits Elixir 1.17+ in the 1.x series; older combinations are unverified. Conversion needs FFmpeg with `-readrate_initial_burst` support.

Configure PostgreSQL as in `config/dev.exs`, then run:

```sh
mix setup
mix phx.server
```

Set `TMDB_READ_TOKEN` in the environment for identification. Set `BOLOGNESA_LIBRARY_ROOTS` to a colon-separated list of media folders; its development default is a temporary directory.

## Development with Docker

This separate Compose project runs Phoenix in development with Tidewave, FFmpeg,
and its own PostgreSQL volume. Docker and Compose are required; Elixir and media
tools do not need to be installed on the host.

```sh
mkdir -p media
sh scripts/dev/ensure.sh
```

Find the local address with `sh scripts/dev/compose.sh port app 4001`. The
first startup downloads dependencies, creates and
migrates the development database, and builds assets. The source tree is mounted
for development; `deps` and `_build` use separate Docker volumes. The media
directory is read-only and available as `/media`. Set `MEDIA_PATH` to use a
different host directory, and `TMDB_READ_TOKEN` for identification.

Each checkout has its own Compose project, database and deterministic local
port. A port collision prevents startup; it does not reuse another checkout.
Tidewave's MCP endpoint is `/tidewave/mcp` on that local address. Its MCP proxy
can use port `4000` inside this checkout's app container. Tidewave can execute
code and access the development database and mounted files, so keep it local.
The helper also makes Git metadata available for Git worktrees. After changing
`Dockerfile.dev`, rebuild with `sh scripts/dev/compose.sh build` and then run
`sh scripts/dev/ensure.sh` again.
Stop the containers with `sh scripts/dev/compose.sh down`; the database
volume is retained. To run checks, use
`sh scripts/dev/compose.sh exec app mix precommit`.

If your Worktrunk setup runs `scripts/dev/teardown.sh` before removing a linked
worktree, that command removes its development containers, image and volumes,
including the development database. It refuses to remove the primary checkout's data.

## Report a problem or propose a change

Describe what you expected, what happened, and how to reproduce it. Include your OS, browser/version, and media container/codecs when relevant. Distinguish actual device results from automated checks. Remove credentials, personal paths, and private media names.

Keep setup and everyday use understandable, stay practical on modest hardware, and make background work recoverable with clear failures. Preserve manual corrections and distinguish verified behavior from expectations.

Discuss larger features before implementing them. Keep fixes focused and add tests when behavior changes. The maintainer chooses scope and cannot promise to merge every proposal.

Code lives in `lib/bolognesa/` and `lib/bolognesa_web/`, with corresponding tests under `test/`. Follow the [project conventions](docs/README.md) and [commit/privacy rules](docs/conventions/commits.md).

## Open a pull request

Explain the problem, the change, and how you checked it. Mention anything you could not verify.

For interface changes, run `make screenshots` and include changed captures; `make check-screenshots` checks them against the pinned browser environment. This requires Docker and Node.js/npm. Synthetic captures verify specific interactions, not general device compatibility.

Contributions are distributed under [MIT](LICENSE); preserve third-party notices.

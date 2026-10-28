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

## Report a problem or propose a change

Describe what you expected, what happened, and how to reproduce it. Include your OS, browser/version, and media container/codecs when relevant. Distinguish actual device results from automated checks. Remove credentials, personal paths, and private media names.

Discuss larger features before implementing them. Keep fixes focused and add tests when behavior changes. The maintainer chooses scope and cannot promise to merge every proposal.

Code lives in `lib/bolognesa/` and `lib/bolognesa_web/`, with corresponding tests under `test/`. Follow the [project conventions](docs/README.md) and [commit/privacy rules](docs/conventions/commits.md).

## Open a pull request

Explain the problem, the change, and how you checked it. Mention anything you could not verify.

For interface changes, run `make screenshots` and include changed captures; `make check-screenshots` checks them against the pinned browser environment. This requires Docker and Node.js/npm. Synthetic captures verify specific interactions, not general device compatibility.

Contributions are distributed under [MIT](LICENSE); preserve third-party notices.

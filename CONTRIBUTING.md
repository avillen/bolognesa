# Contributing to Boloñesa

Thanks for taking a look. This is a personal learning project, and contributions of all sizes are welcome: fixes, refactors, performance work, Elixir/OTP experiments and small interface improvements.

## Get it running

The quickest path is Docker Compose:

```sh
mkdir -p media
docker compose up --build
```

Open [http://localhost:4000](http://localhost:4000) and create the first administrator account. See the README for media mounts, TMDb setup and Docker details.

For native development, install Elixir 1.17 or newer in the supported 1.x series, Erlang/OTP, PostgreSQL and `ffprobe`. Configure PostgreSQL as in `config/dev.exs`, then run `mix setup` and `mix phx.server`. Use `mix test` for the test suite and `mix precommit` for the full local check. Tests use PostgreSQL.

The app is organized by domain context under `lib/bolognesa/`, with the Phoenix interface in `lib/bolognesa_web/` and matching tests under `test/`. See the [architecture decision](docs/decisions/0001-architecture-foundation.md) and [backend conventions](docs/conventions/backend.md) for details. Follow the nearest existing pattern; explain a change when it improves that pattern.

## Propose a change

For a bug, describe what you expected and what happened. For a feature or larger refactor, open an issue or discussion first so we can agree on the smallest useful scope. Experiments are welcome, especially when they are easy to understand and remove if they do not work out.

Please keep changes focused. Prefer a small patch with a clear reason over a broad rewrite. When changing behavior, add a targeted test that describes what a user or caller should observe. Consider the effect on startup time, memory, disk reads and responsiveness, especially on modest hardware.

## Pull requests

Open a pull request with a short description of the problem and the behavior after the change. Include relevant test results and screenshots for interface changes when available. Mention anything you could not verify, such as a browser, device or real media format. Keep personal media, credentials, local `.env` files and private library details out of the PR.

There is no strict template or release process. A clear title, a focused diff and enough context for someone else to review are plenty.

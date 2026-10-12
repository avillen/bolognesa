# Contributing to Boloñesa

This is a personal project developed in public to learn Elixir and build a media center for home use. The maintainer hopes people will try it, share concrete feedback, and help improve the existing experience. The project favors understandable changes, reliable workflows, and good performance on modest hardware.

## Where help is useful

- Try the local setup and point out unclear or broken steps.
- Report reproducible problems, especially around scanning, metadata matching, and browser playback.
- Share results from other operating systems, browsers, media formats, or modest hardware. State what you tested; automated tests do not establish device compatibility.
- Improve focused areas such as reliability, tests, accessibility, documentation, and performance.
- Explore Elixir or OTP ideas when they solve a real problem and remain easy to understand.

Larger features should be discussed before implementation. Ideas are welcome, but the maintainer sets priorities and may not have capacity to support every use case, review every pull request, or merge every proposal. Boloñesa is a learning project, not a promise of production support.

The project is licensed under [MIT](LICENSE). By submitting a contribution, you agree that it can be distributed under that license. Third-party components keep their own license and attribution notices.

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

For a bug, describe what you expected, what happened, and how to reproduce it. Include relevant environment details such as OS, browser, and media container/codecs when known. Remove personal paths, filenames, credentials, and private library details from reports and logs.

For a feature or larger refactor, open an issue or discussion first so the scope can be agreed before implementation. Small experiments are welcome when they are easy to understand and remove if they do not work out.

Please keep changes focused. Prefer a small patch with a clear reason over a broad rewrite. When changing behavior, add a targeted test that describes what a user or caller should observe. Consider the effect on startup time, memory, disk reads and responsiveness, especially on modest hardware.

Use the commit format and privacy checks in the [commit convention](docs/conventions/commits.md). CI scans incoming commits for known secret patterns, but contributors must still review staged changes for personal or operational details that automated scanners may not recognize.

## Pull requests

Open a pull request with a short description of the problem and the behavior after the change. Include relevant test results and screenshots for interface changes when available. Mention anything you could not verify, such as a browser, device, or real media format. Keep personal media, credentials, local `.env` files, and private library details out of the PR.

There is no strict template or release process. A clear title, a focused diff and enough context for someone else to review are plenty.

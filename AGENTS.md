# Bolognesa: shared instructions

A Phoenix web application for learning and home use. Bolognesa's decisions and conventions govern the project. Superpowers and other tools can help with the process, but they must store their artifacts within this repository's structure and respect the user's instructions.

## Session continuity

- At the start, read the [product overview](docs/product.md), [status](docs/status.md), [roadmap](docs/roadmap.md), and applicable conventions. Inspect Git and preserve others' changes.
- Choose a bounded task with acceptance criteria; read the relevant [decisions](docs/decisions/README.md) and conventions. Check the code before assuming a feature exists.
- After significant work, run `mix precommit` and the relevant checks; fix failures and update `docs/status.md` with the actual status, verification, blockers, and next step. Do not claim deployment or device compatibility without evidence.
- If work remains incomplete, record the files or branch, pending steps, failed command, and reproducible symptoms. Do not store credentials or private media inventories.
- Mark a milestone complete only when the criteria in `docs/roadmap.md` are met. Avoid empty plans or speculative implementations.

## Documentation organization

Consult [docs/README.md](docs/README.md) and follow the [documentation convention](docs/conventions/documentation.md). Keep public content in English and free of private details. Status is a snapshot, not a history; when temporary work is finished, remove its notes or summarize lasting information in a convention or decision. Do not create directories for individual tools or duplicate instructions in agent-specific files.

## Conventions by area

| Area | Reference |
| --- | --- |
| Elixir modules, public APIs, and Mix | [Elixir](docs/conventions/elixir.md) |
| Domain, application, persistence, integrations, and authorization | [Backend](docs/conventions/backend.md) |
| LiveViews, reducers, forms, and view state | [Frontend](docs/conventions/frontend.md) |
| Phoenix 1.8, HEEx, Ecto, Tailwind, hooks, and interaction | [Phoenix and UI](docs/conventions/phoenix.md) |
| Functional changes, tests, and refactors | [Testing](docs/conventions/testing.md) |
| Logs, errors, and background jobs | [Observability](docs/conventions/observability.md) |
| Project documentation | [Documentation](docs/conventions/documentation.md) |

Read all applicable conventions before modifying an area.

## Operations

Before deploying, read `make help` and the [shared deployment guide](deploy/compose/README.md). Configure the installation with `.env.deploy` and use `make deploy-release` for a published commit on `main`. Record the actual CI run, image digest, backup, and verification; preserve the project, data, and internal paths when updating.

# Project conventions

Read the conventions for the area you change. Each topic has one reference; link to it instead of copying its rules.

| Reference | Owns |
| --- | --- |
| [Elixir](elixir.md) | Types, public API names, module layout, and language idioms |
| [Backend](backend.md) | Context boundaries, domain models, ports, persistence, transactions, and durable work |
| [Frontend](frontend.md) | Screen organization, reducers, presentation state, browser ownership, and localization |
| [Phoenix and UI](phoenix.md) | Routing, web security, HEEx, forms, LiveView APIs, hooks, and accessibility |
| [Testing](testing.md) | Test design, isolation, synchronization, and verification scope |
| [Observability](observability.md) | Events, logs, metrics, privacy at emission, and delivery limits |
| [Documentation](documentation.md) | Document placement, release notes, public content, and maintenance |
| [Commits](commits.md) | Commit messages, staged review, and secret scanning |

These are Bolognesa's rules, not a claim that its architecture is required by Elixir or Phoenix. Context-owned domain models, ports, screen-local reducers, lookup results, and struct layout are deliberate project choices. Their rationale belongs in [architecture decisions](../decisions/README.md).

Use APIs supported by `mix.lock` and the existing asset setup. Runtime versions and setup belong in [CONTRIBUTING](../../CONTRIBUTING.md#native-development). Follow [Changing conventions](documentation.md#changing-conventions) for sources, tools, review, and verification when updating these rules.

Keep conventions short and durable. Put runnable procedures in guides such as [playback verification](../playback-testing.md), implementation rationale in decisions, and pending work or verification evidence in GitHub issues and pull requests. Historical decisions may describe superseded mechanisms; follow their replacement links and the current conventions.

# 0014. Parallel categories for ports and infrastructure

Status: Accepted and implemented locally.

## Context

Ports and adapters had been grouped together despite representing repositories, readers, external providers, and technical services. Their responsibilities were hard to locate by directory.

## Decision

Within each context, use parallel `Repositories`, `Readers`, `Providers`, and `Services` categories under `Application.Ports` and `Infrastructure`. Name each behaviour and adapter descriptively; the category reflects contract responsibility, not implementation technology. An Ecto reader belongs under `Readers`; an Ecto repository belongs under `Repositories`.

Keep mappers and private collaborators beside the responsible adapter. Global Ecto schemas remain in `Bolognesa.Infrastructure.Persistence`; workers and recovery policies remain under `Infrastructure.Jobs`. Do not move unrelated modules solely for symmetry.

## Consequences

The namespace makes contract families easier to find. Moving modules requires updating references and tests but does not change callbacks, public facades, persistence, migrations, or behavior.

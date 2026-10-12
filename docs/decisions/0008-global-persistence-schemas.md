# 0008. Global namespace for persistence schemas

Status: Accepted and implemented locally; namespace location updated on 2026-10-11.

## Context

Ecto schemas represent application tables, including tables joined by readers in several contexts. Nesting shared schemas under a repository made them appear owned by one repository.

## Decision

Place one schema module per table in `Bolognesa.Infrastructure.Persistence`, without context subdirectories. Give schemas globally unique names, including `IdentificationEventSchema` and `InspectionEventSchema`. Adapters import the schemas needed for their queries; mappers stay beside their adapters. Sharing a schema does not grant another context write ownership.

## Consequences

Cross-table readers no longer depend on another repository's namespace. The move changes module names and references, but not tables, fields, migrations, or persisted data. Cross-context projections remain inside explicit read adapters.

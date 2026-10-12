# 0012. Shared catalog identity and atomic identification writes

Status: Implemented locally; deployment status is tracked in [project status](../status.md).

## Context

Movie associations and playback authorization depended directly on the `movies` table. Supporting series requires a stable identity shared by several kinds of catalog details.

## Decision

- `catalog_entries` stores a shared ID, kind, and unique `(provider, resource_type, provider_id)` reference. Current provider data is explicitly constrained; new resource kinds require real use cases and migrations.
- `movies.id` is a restrictive PK/FK to the shared identity, with movie-specific fields only. Existing IDs and URLs are preserved.
- Identification creates or reuses identity and details through its own repository collaborator and commits them with the file association in one transaction. Retries preserve existing metadata; uniqueness handles concurrent versions.
- Catalog reads identities and details through its own adapters and models. It does not import Identification models or mappers.
- Playback validates a confirmed catalog/file relationship without depending on `MovieSchema`. Routes translate movie-specific IDs at the boundary.
- Preserve request tokens, statuses, revisions, manual corrections, events, and job arguments. Keep external queries outside transactions.

This partially supersedes [decision 0005](0005-catalog-identification.md) on identity and write ownership.

## Consequences

Movie reads add a join, and each context maintains its own models. A standalone catalog-entry creation flow should revisit ownership with that specific use case. Schema migrations and application code must be activated together; rollback must preserve references and later-created movie IDs. No series behavior follows from this identity decision alone.

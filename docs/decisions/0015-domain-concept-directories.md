# 0015. Domain directories by concept type

Status: Accepted and implemented in domain contexts.

## Context

As domain modules grew, entities, candidates, selections, and rules shared a single directory. The code should make domain concepts easier to find without imposing artificial categories.

## Decision

Organize modules under `domain/entities/`, `value_objects/`, `policies/`, and `services/` where those categories contain real modules. Optional subdirectories may group cohesive subdomains. Use namespaces that match paths. Do not create an `aggregates/` category solely for aggregate roots; do not create empty or one-module-per-folder taxonomies.

Classify read projections by their meaning and lifecycle, not just their filename. Reserve `services/` for domain rules that do not naturally belong to an entity, value object, or policy. Preserve context boundaries, ports, persistence, and behavior when moving modules.

## Consequences

Namespaces gain segments and consumers/tests must be updated. The organization makes concepts visible but requires judgment to avoid over-classification. See [backend conventions](../conventions/backend.md).

# Backend architecture and conventions

This is the current backend reference. Update it when an agreed rule changes. Open questions should be resolved while designing the relevant feature; this document is not an implementation plan.

## Architecture

Bolognesa is one Phoenix application organized into bounded contexts. Each context follows domain-driven design and hexagonal architecture:

- **Domain** owns entities, value objects, policies, invariants, and transitions. It does not depend on Phoenix, Ecto, HTTP clients, external processes, or the filesystem.
- **Application** coordinates authorization, domain behavior, and ports. It defines transaction boundaries.
- **Ports** are behaviours for concrete needs outside the application layer.
- **Infrastructure** implements persistence, filesystem access, HTTP providers, media tools, and background jobs.
- A context's public facade is its interface. Other contexts do not call its internal modules, repositories, or schemas.

Use cases do not call another context's use cases. Share business behavior through the owning context's facade; keep cross-context technical utilities neutral and free of business rules. Inject adapters outside the domain. Tests must not mutate global configuration concurrently.

Name ports after their responsibility (`LibraryRepository`, `MoviesReader`) and adapters after their technology (`EctoLibraryRepository`). Within each context, mirror `Application.Ports` and `Infrastructure` categories: `Repositories`, `Readers`, `Providers`, and `Services`. Keep mappers and collaborators beside the adapter that owns them. Global Ecto schemas live under `Bolognesa.Infrastructure.Persistence`; job workers and recovery policies live under `Infrastructure.Jobs`.

Organize domain modules by concept type where useful: `entities/`, `value_objects/`, `policies/`, `services/`, and `read_models/`. Create only categories that contain real modules; group by subdomain only when that keeps a cohesive set together. Do not create an `aggregates/` category merely to label aggregate roots.

## Domain and persistence boundaries

- Keep aggregates small and use them to define consistency boundaries. Do not load every file in a library or every episode in a series into memory.
- Each context owns writes to its data. Cross-context references use IDs and public facades.
- Repositories expose domain needs, not Ecto queries or changesets. Do not create a generic CRUD repository.
- Business results from repositories use domain models, not Ecto schemas, application DTOs, or untyped maps. Type compound results and explicit scalar metadata in the port contract.
- Use cases build public DTOs from domain results. Keep pure `from_domain/1` conversion on the DTO; it must not perform I/O or call facades. Simple response containers can be assembled by the use case.
- Changesets enforce persistence requirements; domain rules belong in the domain. Database constraints protect uniqueness and integrity under concurrency.
- Keep transactions short. Do not hold one open during HTTP calls, scans, or media inspection. Use a transaction port when the application needs atomic work without depending on `Ecto.Multi`.
- Read adapters may join tables across contexts but return models owned by the reading context. A read join does not grant write ownership.
- Entities are values, not OTP processes. Use processes for coordination, supervision, concurrency, and temporary state.
- Do not introduce event sourcing or full CQRS without a concrete requirement.

## Context responsibilities

### Identity

Owns accounts, credentials, sessions, and authorization. Initial setup creates one administrator; there is no public registration or hard-coded user. Protected use cases receive an authenticated `Actor` established by trusted authentication, never an arbitrary client-supplied ID. Authorization is enforced in the backend, including media delivery.

### Libraries

Owns configured sources, file inventory, scans, and technical inspection. A file is identified within a library by its relative path; the original path bytes are preserved. Size and modification time define the observed revision. A rename creates a new inventory entry; content deduplication is not promised.

Only a complete successful scan can mark unseen files as absent. An inaccessible source or partial scan must not cause bulk removals. Repeated scans reconcile without duplicates. Original media is read-only and is never moved, renamed, or deleted by the application.

### Catalog

Owns media works independently of physical file availability. Movies, series, seasons, and episodes have their own catalog identities and details. Season zero represents specials; episodes use positive numbering. The common catalog identity has a unique external provider/resource reference. Details use a restrictive PK/FK to that identity.

Catalog reads through its own models and adapters. Identification owns creation or reuse of catalog identities during matching, together with the file association in its transaction. A standalone catalog-entry creation flow requires revisiting that ownership with a concrete use case.

### Identification

Owns file-to-work decisions, candidates, provenance, and manual corrections. Every file has one decision; confirmed relationships are ordered and replaced atomically. A movie selects one work. A series file may select a bounded set of episodes from one season. Unconfirmed decisions expose no active relationships.

Manual corrections must survive later automatic results, retries, and concurrent work. Persisted request tokens and revisions reject stale responses. External provider calls happen outside transactions. TMDb receives only the inferred title and year, not local paths or library names; enabling lookup requires a runtime read token.

### Playback

Owns authorization, file selection, delivery strategy, and temporary playback sessions. Only confirmed movies and episodes are playable; series and seasons are containers. Direct delivery and the optional FFmpeg/HLS path both revalidate the actor, current association, file availability, and revision. Byte-range requests support seeking. A file linked to several episodes plays in full and the UI explains that limitation.

Do not assume a server can transcode fast enough or that a browser supports a given container and codec. Verify real formats and devices separately.

## Background work, events, and recovery

Run long tasks outside web requests with durable jobs, bounded retries, and measured concurrency. Workers call use cases; the domain does not depend on Oban. Delivery is at least once, so consumers tolerate duplicates. A generation or request token rejects stale results; do not promise exactly-once execution.

When a durable side effect follows a database change, record its outbox event in the same transaction and dispatch it after commit. PubSub may notify connected clients but is not a source of truth or a recovery mechanism. Authorize subscriptions and actions independently; topic names do not grant access. Notifications contain minimal references, never private paths or media content.

Transient failures retry within a bound. Terminal failures remain visible and can be explicitly retried. Logs follow [observability conventions](observability.md).

## Use cases and verification

Use case names describe user or system outcomes; do not create a module for every trivial operation. Apply [testing conventions](testing.md): test domain rules without a database, application behavior through public contracts, persistence guarantees with PostgreSQL, and UI behavior through LiveViewTest. Use controlled external resources; ordinary tests do not depend on public providers, a NAS, or a TV.

Meaningful implementation changes run `mix precommit`. Automated tests do not establish deployment, device compatibility, or real-world media performance.

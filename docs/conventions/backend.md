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

## Queries and migrations

- Select only the data the operation needs. Load related records in batches or joins instead of issuing one query per result; add a query-count regression when collection growth could reintroduce an N+1 problem.
- Bound collection reads and background batches. Paginated queries need deterministic ordering with a unique tie-breaker, such as title followed by ID. Define ordering and missing-value behavior in the read contract when callers depend on them.
- Review indexes against actual filters, joins, and ordering. Use query plans and representative data when investigating expensive reads; avoid adding indexes solely because a column exists.
- Review migrations for table size, lock duration, backfill cost, and compatibility with application activation. Choose staged changes or bounded backfills when a single migration would hold locks or run for too long.
- Preserve existing identities and durable user data. Make rollback behavior explicit; refuse a destructive rollback when later-created data cannot be represented safely. Verify migrations and relevant constraints with PostgreSQL, following the [deployment guide](../../deploy/compose/README.md) for release operations.

## Context responsibilities

### Accounts

Owns accounts, credentials, sessions, and authorization through `Bolognesa.Accounts`. Persistence uses the `accounts_users` and `accounts_sessions` tables. Initial setup creates one administrator; there is no public registration or hard-coded user. Protected use cases receive an `AuthenticatedUser` established by trusted authentication, never an arbitrary client-supplied ID. `User` represents the persisted account inside Accounts; `AuthenticatedUser` represents the verified caller supplied to protected operations. Its `from_user/1` conversion copies account data and does not authenticate a caller by itself. Authorization is enforced in the backend, including media delivery.

### Libraries

Owns configured sources, file inventory, scans, and technical inspection. A file is identified within a library by its relative path; the original path bytes are preserved. Size and modification time define the observed revision. A rename creates a new inventory entry; content deduplication is not promised.

Only a complete successful scan can mark unseen files as absent. An inaccessible source or partial scan must not cause bulk removals. Repeated scans reconcile without duplicates. Original media is read-only and is never moved, renamed, or deleted by the application.

### Movies and Series

Movies owns movie identities, metadata, versions, file decisions, matching, corrections, requests, durable jobs, and recovery. Series independently owns the equivalent series/season/episode hierarchy and ordered episode selections. Both expose their own public facades; neither imports the other's internal models or adapters. Catalog and Identification are no longer business contexts. Persisted schemas remain under `Bolognesa.Infrastructure.Persistence`.

Each content table has an independent generated ID and unique `(provider, provider_id)` reference. A movie decision stores a nullable scalar `movie_id`; a series decision stores ordered episode associations. Confirmed relationships and newly created works commit together. Series selections contain at most one hundred unique episodes from one season and are replaced atomically. Unconfirmed decisions expose no active relationships. See [decision 0019](../decisions/0019-content-context-boundaries.md).

A single-episode file decision can carry a filename part number from 1 to 100. Parts share the provider episode identity; season display entries and continuation distinguish them. Whole-episode alternatives remain separate from part versions. Known missing parts and numbering gaps stop automatic continuation. See [decision 0025](../decisions/0025-consecutive-episode-parts.md) for naming, activation, navigation, and rollback contracts.

Manual corrections survive later automatic results, retries, and concurrent work. Persisted request tokens and revisions reject stale responses; manual provider lookups recheck the observed file revision under lock. Provider calls remain outside transactions. Movies and Series share only the neutral TMDb HTTP transport under `Bolognesa.Infrastructure.Providers`; their provider ports, endpoints, and payload mappers remain context-owned. TMDb receives only the inferred title and year, never local paths or library names; enabling lookup requires a runtime read token.

Libraries explicitly routes inventory handoffs to the owning facade inside the inventory transaction. Inventory, owner requests, and their Oban jobs commit or roll back together. Each owner revalidates content type, and filters backfill and recovery before batch limits. Workers and reconciler processes are separately named; both video owners initially share the existing `identifications` queue and its concurrency budget.

### Music

Owns library-local tracks, artists, albums, file associations, import attempts, and musical read models. Tracks have stable database IDs and one association per inventory file; copies remain distinct. Grouping preserves library and source boundaries rather than merging unrelated releases.

Libraries owns sanitized observations; Music accepts them through its transaction-aware facade and owns pending import state, linked jobs, and recovery from acceptance onward. Imports revalidate the current observation before writing, tolerate duplicate delivery, and reject stale revisions or inspection tokens. Reads are authorized and library-scoped; Playback reauthorizes each selected track.

Identity keys, import locking and recovery, browsing limits, and album playback contracts are defined in [decision 0018](../decisions/0018-local-music-catalog.md). Current listening behavior and verification limits belong in [project status](../status.md).

### Playback

Owns authorization, file selection, delivery strategy, and temporary playback sessions. Confirmed movies and episodes, and music tracks imported from a current successful audio inspection, are playable; series and seasons are containers. Keep the distinction visible in the API: `start_video` and `start_track` select their respective sources, and video delivery/preparation/transcoding operations carry `video` in their names. Music selection is track/file based and uses a separate endpoint so its numeric IDs cannot resolve video works. Video calls use explicit `{:movie, id}` or `{:episode, id}` references. Direct delivery and the optional FFmpeg/HLS path both revalidate the actor, current association, file availability, and revision. HLS sessions bind actor, typed content reference, file, and revision. Only a successful inspection of the current revision supplies technical metadata; video direct delivery remains available without inspection. Byte-range requests support seeking. A file linked to several episodes plays in full and the UI explains that limitation.

Do not assume a server can transcode fast enough or that a browser supports a given container and codec. Verify real formats and devices separately.

## Background work, events, and recovery

Run long tasks outside web requests with durable jobs, bounded retries, and measured concurrency. Workers call use cases; the domain does not depend on Oban. Delivery is at least once, so consumers tolerate duplicates. A generation or request token rejects stale results; do not promise exactly-once execution.

When durable work uses Oban in the same PostgreSQL database, insert its job and request state in the same transaction and link the job before commit. An additional outbox is unnecessary for this boundary. Retain an outbox when delivery has a separate consistency boundary or an explicit existing contract pending migration. PubSub may notify connected clients but is not a source of truth or a recovery mechanism. Authorize subscriptions and actions independently; topic names do not grant access. Notifications contain minimal references, never private paths or media content.

Application use cases signal confirmed status changes through a context-owned notification port after repository operations succeed. Repositories persist and return results; they do not publish PubSub hints. Recovery results retain references changed by successful transactions even when later work fails, so application can notify those committed changes before returning the error. Notification adapters define topics and payloads and contain delivery failures, preserving successful persistence. Authorize subscriptions at the context facade and keep domain models independent of notification transport.

Transient failures retry within a bound. Terminal failures remain visible and can be explicitly retried. Logs follow [observability conventions](observability.md).

## Use cases and verification

### DTO ownership and location

Use a domain model for a business concept or invariant, including a context-owned read model when a projection expresses domain meaning. Use an application DTO when a use case needs a distinct public input or output shape. A simple scalar, tuple with a named type, or explicitly typed container is enough when no separate model or conversion adds meaning; do not wrap every result in another struct. Repositories and readers still return domain results as required above, and persistence schemas never become public responses.

Place DTOs exclusive to a use case beside it, in a directory named after the use case. For example, `application/use_cases/get_movie.ex` owns `application/use_cases/get_movie/response.ex`, with module name `Application.UseCases.GetMovie.Response` under the context namespace. Use `Request` and `Response` where appropriate; do not introduce an input DTO solely to wrap a simple ID or scalar argument.

Keep DTOs shared by multiple use cases in the same context's `application/dto/`, under `Application.Dto`. Share a DTO when the operations use the same contract and should evolve together, not merely because their current fields match. A use case must not depend on another use case's exclusive DTO; promote a genuinely shared contract to `application/dto/`, or give each operation its own DTO when their needs differ.

DTOs representing HTTP payloads or external provider formats belong to their adapters. Application DTOs remain independent of those technologies, and domain models do not depend on application DTOs.

Apply this convention to new and revised contracts. Existing DTOs will be reorganized incrementally; their current location does not imply that they are shared.

### Verification

Use case names describe user or system outcomes; do not create a module for every trivial operation. Apply [testing conventions](testing.md): test domain rules without a database, application behavior through public contracts, persistence guarantees with PostgreSQL, and UI behavior through LiveViewTest. Use controlled external resources; ordinary tests do not depend on public providers, a NAS, or a TV.

Meaningful implementation changes run `mix precommit`. Automated tests do not establish deployment, device compatibility, or real-world media performance.

# Backend architecture and conventions

This is the current backend reference. Update it when an agreed rule changes. Open questions should be resolved while designing the relevant feature; this document is not an implementation plan.

## Architecture

Bolognesa is one Phoenix application organized into bounded contexts. Context boundaries follow [decision 0001](../decisions/0001-architecture-foundation.md); add abstractions for concrete responsibilities:

- **Domain** owns entities, value objects, policies, invariants, and transitions. It does not depend on Phoenix, Ecto, HTTP clients, external processes, or the filesystem.
- **Application** coordinates authorization, domain behavior, and ports. It defines transaction boundaries.
- **Ports** are behaviours for concrete needs outside the application layer.
- **Infrastructure** implements persistence, filesystem access, HTTP providers, media tools, and background jobs.
- A context's public facade is its interface. Other contexts do not call its internal modules, repositories, or schemas.

Use cases do not call another context's use cases. Share business behavior through the owning context's facade; keep cross-context technical utilities neutral and free of business rules. Inject adapters outside the domain. Test isolation follows [testing conventions](testing.md).

Name ports after their responsibility (`LibraryRepository`, `MoviesReader`) and adapters after their technology (`EctoLibraryRepository`). Within each context, mirror `Application.Ports` and `Infrastructure` categories: `Repositories`, `Readers`, `Providers`, and `Services`. Keep mappers and collaborators beside the adapter that owns them. Global Ecto schemas live under `Bolognesa.Infrastructure.Persistence`; job workers and recovery policies live under `Infrastructure.Jobs`.

Organize domain modules by concept type where useful: `entities/`, `value_objects/`, `policies/`, `services/`, and `read_models/`. Create only categories that contain real modules; group by subdomain only when that keeps a cohesive set together. Do not create an `aggregates/` category merely to label aggregate roots.

## Domain and persistence boundaries

- Keep aggregates small and use them to define consistency boundaries. Do not load every file in a library or every episode in a series into memory.
- Each context owns writes to its data. Cross-context references use IDs and public facades.
- Repositories expose domain needs, not Ecto queries or changesets. Do not create a generic CRUD repository.
- Business results from repositories use domain models, not Ecto schemas, application DTOs, or untyped maps. Type compound results and explicit scalar metadata in the port contract.
- Use cases build public DTOs from domain results. Keep pure `from_domain/1` conversion on the DTO; it must not perform I/O or call facades. Simple response containers can be assembled by the use case.
- Changesets enforce persistence requirements; domain rules belong in the domain. Database constraints protect uniqueness and integrity under concurrency.
- Keep transactions short. Do not hold one open during HTTP calls, scans, or media inspection. Use a transaction port to keep application code independent of Ecto. In adapters, prefer `Repo.transact/2`; its function must return `{:ok, result}` or `{:error, reason}`. Use `Ecto.Multi` for named, composable database steps. Do not mechanically rename `Repo.transaction/2`: its function return semantics differ. See the [Ecto transaction API](https://hexdocs.pm/ecto/Ecto.Repo.html#c:transact/2).
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

| Context | Owns | Contract reference |
| --- | --- | --- |
| Accounts | Credentials, revocable sessions, authorization, and account preferences | [Initial access](../decisions/0002-initial-access.md), [locale](../decisions/0016-user-locale-and-settings.md) |
| Libraries | Read-only sources, inventory, recoverable scans, and technical inspection | [Scans](../decisions/0003-recoverable-library-scans.md), [inspection](../decisions/0004-technical-media-inspection.md) |
| Movies and Series | Independent identities, metadata, matching, manual corrections, file associations, and recovery | [Content boundaries](../decisions/0019-content-context-boundaries.md), [episode parts](../decisions/0025-consecutive-episode-parts.md) |
| Music | Library-local tracks, artists, albums, imports, listening activity, and musical read models | [Local music](../decisions/0018-local-music-catalog.md), listening rules below |
| Playback | Authorized source selection, delivery plans, and temporary video sessions | [Direct delivery](../decisions/0006-authorized-direct-playback.md), [FFmpeg/HLS](../decisions/0011-live-transcoding.md) |

Protected operations receive an `Accounts.Domain.Entities.AuthenticatedUser` established by trusted authentication. Constructing it from a `User` copies data; it does not authenticate a caller. Playback uses explicit `{:movie, id}` or `{:episode, id}` references and separate track endpoints so overlapping numeric IDs cannot select another content type.

Original media remains read-only. Inventory identity follows library and relative path, with size and modification time identifying the observed revision. Only a complete successful scan can mark unseen files absent. Manual corrections take precedence over later automatic results; request tokens and revisions reject stale work. Libraries routes handoffs through explicit transaction-aware owner facades; inventory, requests, and jobs commit together. [Decision 0020](../decisions/0020-direct-durable-jobs.md) supersedes the older outbox mechanisms in the linked records.

### Music listening contracts

Listening activity stores at most one latest timestamp per account and track. The browser reports after 30 seconds of observed playback, or half a shorter track; pauses and seeks do not count. Retry transient failures only while that selection remains active. This is a best-effort client observation. Refreshes and replacements at the same path retain activity; renames create a new identity. Deleting an account or track deletes its activity.

Album `last_played_at` is the account's latest activity across its current tracks, including temporarily missing files; no activity returns `nil`. It is derived independently of browsing filters and pagination and does not prove completion. Albums without available files remain hidden.

Recent listening returns at most three distinct available albums in the selected library, or across libraries when none is selected. Order by activity descending, then album ID ascending; choose the latest heard track by activity descending, then track ID ascending. No activity returns an empty list; failed reads return an error. Continue must select that exact track from the current authorized queue, preserving a missing selection on retry. Replay starts at the beginning when it is the last available track. Album order is disc, track, path, ID, with missing numbers last. Do not store a separate album-completion state.

## Background work, events, and recovery

Run long tasks outside web requests with durable jobs, bounded retries, and measured concurrency. Job uniqueness limits duplicate insertion; it does not guarantee idempotent execution or serialize workers. Workers call use cases; the domain does not depend on Oban. Delivery is at least once, so consumers tolerate duplicates. A generation or request token rejects stale results; do not promise exactly-once execution.

When durable work uses Oban in the same PostgreSQL database, insert its job and request state in the same transaction and link the job before commit. An additional outbox is unnecessary for this boundary; see [decision 0020](../decisions/0020-direct-durable-jobs.md). Retain an outbox when delivery has a separate consistency boundary or an explicit existing contract pending migration. PubSub may notify connected clients but is not a source of truth or a recovery mechanism. Notifications contain minimal references, never private paths or media content.

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

Use case names describe user or system outcomes; do not create a module for every trivial operation. Follow [testing conventions](testing.md) for coverage, commands, and evidence.

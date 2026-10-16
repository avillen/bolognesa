# 0019. Content-owned contexts

Status: Implemented and reviewed. Deployment evidence is tracked in [project status](../status.md).

## Purpose

Bolognesa should accommodate contributions that grow movie, series, and music capabilities independently. Organize business ownership around those three domains while retaining one Phoenix application, PostgreSQL database, and deployment. Preserve existing product capabilities. The maintainer explicitly permits breaking changes and discarding the entire database followed by setup, source configuration, scanning, and identification again. Existing IDs, URLs containing those IDs, accounts, corrections, jobs, and other persisted records do not need migration or compatibility.

The requested final architecture review is part of completion. Its outcome may be to retain duplication, share technical infrastructure, propose a shared business context, or record follow-up work. It does not presume an extraction is necessary.

## Alternatives

1. **Content-owned contexts (recommended):** Movies, Series, and Music own their reads, identification/import, metadata, associations, tables, and recovery. This makes contributions local to their business area, at the cost of some initially duplicated identification machinery.
2. **Responsibility-owned contexts:** Extend Catalog and Identification to music. This offers a consistent pipeline but concentrates type-specific changes in two growing contexts.
3. **Facade-only separation:** Introduce Movies and Series while keeping Catalog and Identification as their implementations. This can be an intermediate migration step, but does not meet the ownership goal as a final design.

## Target ownership

| Context | Owns |
| --- | --- |
| Identity | Accounts, sessions, and authorization policy |
| Libraries | Sources, inventory, scans, technical observations, and durable inspection handoffs |
| Movies | Movie identities and metadata, versions, file identification, review, corrections, requests, outbox delivery, and recovery |
| Series | Series/season/episode identities and metadata, ordered file associations, identification, review, corrections, requests, outbox delivery, and recovery |
| Music | Existing local track/artist/album identities, import, grouping, browsing, and import recovery |
| Playback | Authorized file selection and delivery, direct/HLS strategy, and temporary playback sessions |

Catalog and Identification cease to be business contexts. No universal media entity, identification workflow, generic repository, new dependency, umbrella application, or separate service is introduced. Existing shared technical utilities remain unless their ownership becomes invalid after the split.

## Boundaries and contracts

- `Bolognesa.Movies` and `Bolognesa.Series` become the public facades for their reads and identification operations. Models, DTOs, ports, providers, repositories, and tests move into the owning namespace. Music keeps its current facade and behavior.
- Movie and series identification decisions initially have separate context-owned domain models and adapters, even where their current fields or transitions coincide. Neither context imports the other's internal models or repositories.
- Each context commits its identity/details and confirmed file association together. Provider calls stay outside transactions. Existing manual precedence, token/revision checks, lock order, and bounded retries remain intact.
- Libraries routes scan handoffs by the immutable library content type through explicit Movies or Series facade operations. Preserve the existing transactional integration: inventory changes, identification requests, and their outbox events commit or roll back together. Do not replace this with an after-commit best-effort notification.
- The scan integration may retain the existing explicitly named transaction-aware facade contract. Passing a repository is an infrastructure integration exception already used by the project, not a general permission for contexts to call one another's internal repositories.
- Dispatch, backfill, retry, reconciliation, and all mutation entry points are restricted to the owning library content type. Apply type filters before batch limits. Wrong-type calls cannot change another context's state or consume its recovery budget.
- Frontend callers use the owning facade and DTOs. Keep screen organization and user-visible behavior; route and API changes are allowed when they clarify content identity. Do not redesign templates or interaction as part of this refactor.
- Playback continues to use its own projections and authorized readers. Cross-context table joins remain permitted by the backend convention. It need not call both new contexts to resolve a file, and music/video IDs remain distinguished at the existing endpoints.
- Persisted schemas stay under `Bolognesa.Infrastructure.Persistence`. Moving a business module does not require moving its schema.

## Persistence and clean rebuild

Remove `catalog_entries`, `media_identifications`, `identification_entries`, and `media_identification_events` from the target schema. Do not preserve a universal video ID or a central identification store.

- `movies` owns an independently generated primary key, movie metadata, and its provider reference with a database uniqueness constraint.
- `series`, `seasons`, and `episodes` own independent primary keys, explicit hierarchy foreign keys, metadata, and the provider references/uniqueness needed by their existing matching behavior.
- `movie_identifications` owns one decision per inventory file, current revision/token, provenance, candidates, job/recovery fields, and a nullable `movie_id`. Only confirmed decisions have an active movie reference. Several file decisions can point to the same movie as versions.
- `series_identifications` owns one decision per inventory file and the equivalent series-specific decision state. `series_identification_episodes` owns its ordered episode references, with uniqueness and positive-position constraints. Preserve the bounded, same-season, all-or-nothing selection policy.
- `movie_identification_events` and `series_identification_events` are separate durable outboxes. Each domain owns its dispatcher, worker, backfill, and reconciler.
- Existing Libraries, Music, Identity, and Oban schemas remain unless a concrete dependency requires a change. The allowed whole-database reset also clears old accounts, library configuration, and jobs; source media is never modified.

Keep current TMDb matching and local music identity behavior. Introducing local unmatched video works or recording/release deduplication is outside scope. Do not add a universal provider-reference table without a concrete requirement.

Add an explicit schema migration that replaces the obsolete video tables and constraints with the target tables. Fresh database setup through the full migration chain and rebuilding an existing disposable database must both work. The change does not backfill data or support restoring old identities. A destructive reverse migration must refuse rather than imply it can recover removed data; returning to the old application requires rebuilding the old database separately.

Document the one-time reset procedure: stop the application and workers, reset the configured Bolognesa database including persisted Oban jobs, run migrations with the new application, restart, create the administrator, configure sources, scan, and identify again. Do not ship old-worker adapters, dual writes, transitional tables, or fallback APIs. Deployment and reset of a running installation require an explicitly authorized operation beyond local implementation checks; follow the shared deployment guide and retain a validated pre-reset backup.

Retain the existing video Oban queue and concurrency budget initially. Each context has separately named dispatcher/reconciler processes and its own outbox. Preserve startup controls used by tests. Recovery handles new jobs only, with the current duplicate/stale/retry guarantees.

## Explicit playback identity

Independent movie and episode sequences can produce equal numeric IDs. Use a Playback-owned typed reference, `{:movie, id}` or `{:episode, id}`, through video selection, preparation, delivery, compatible playback, session lookup, and source revalidation. Keep the existing track-specific path for music. Controllers construct the type from their movie/episode route; no request infers it from a bare numeric ID.

Replace `catalog_entry_id` in playback contracts, temporary sessions, and web presentation state with the typed reference or explicitly named type and ID fields. Bind HLS sessions to actor, content type, content ID, file ID, and revision. Equal movie and episode IDs must never authorize each other's direct or HLS endpoints. Playback continues reading through its own adapters rather than importing content-domain entities.

## Implementation sequence

Stages are dependent work within one refactor branch, not independently deployable releases. The detailed plan must name their contracts and focused checks; integration becomes releasable only after stage 5. No compatibility layer is required to make intermediate commits deployable.

1. **Establish the baseline and target contracts.** Run current focused coverage and `mix precommit`; record actual results. Specify owner facades, independent schemas, typed playback reference, transactional handoffs, and observable regressions for wrong-type writes and overlapping IDs.
2. **Build independent persistence and movie ownership.** Add the destructive schema migration and Movies models, DTOs, queries, identification, providers, repositories, outbox, and recovery. Update movie fixtures and callers. Keep the existing matching and correction behavior while removing generic catalog identity from this domain.
3. **Build series ownership.** Introduce Series reads, hierarchy, identification, corrections, providers, repositories, outbox, and recovery against the independent schemas. Preserve ordered multi-episode replacement and whole-selection atomicity. Update series/episode fixtures and callers.
4. **Wire Libraries, Playback, and runtime processes.** Route scan transactions to the owner, adopt typed video references throughout direct/HLS playback, update supervision/configuration, test support, and development scripts. Remove all reliance on generic catalog/identification tables or old worker names.
5. **Remove obsolete boundaries and verify the rebuilt application.** Delete Catalog/Identification facades and internals. Update conventions, decision links, setup/reset instructions, and status. Verify fresh setup and reset on disposable databases; exercise administrator setup, configuration, scan, identification/correction, browsing, and authorized playback. Run `mix precommit` and relevant existing screenshot/browser checks. Report actual evidence and any remaining limitations.
6. **Review the resulting boundaries.** Inspect real implementations after all three content contexts work. Record the candidate assessment and conclusion in this decision or a linked successor. Complete the review even if its conclusion is that no extraction is justified.

## Verification and acceptance

Use current behavior tests as refactor protection. Reorganize them with their owner without weakening their assertions. Add coverage only for meaningful gaps introduced or exposed by the split.

- The new application initializes from an empty database and after a documented reset. No legacy rows, worker module names, or identity mappings are required. Old data is explicitly disposable; no reset touches source media.
- Movie and series public mutation APIs reject files from another library type; retries, backfill, outbox delivery, and recovery do not mutate the other domain's rows. Mixed-library inventory batches cannot starve the owning type by applying the limit first.
- Duplicate jobs, stale tokens/revisions, provider failures, manual-vs-automatic races, and interrupted-job recovery retain existing behavior for the new workers.
- Injected persistence failure rolls back inventory/request/event together and identity/details/association together. Multi-episode selection never persists only a subset.
- Library scoping, literal search, pagination, constant-query episode/version reads, review screens, correction feedback, and authenticated playback keep their existing contracts.
- Music import, conservative grouping, inspection handoff, retry, and bounded album playback remain unaffected after reimport. Equal movie/episode/track IDs cannot select another content type, including through HLS session and segment endpoints.
- No production caller imports removed Catalog/Identification modules or references obsolete tables. No Movies/Series/Music context imports another content context's internal modules. Global persistence schemas and Identity's Actor contract remain permitted contracts under existing conventions.
- Tests run against controlled providers and PostgreSQL. Record actual commands and results; automated success does not establish deployment or device compatibility.

Existing regression anchors include `test/bolognesa/movies/`, `test/bolognesa/series/`, `test/bolognesa/libraries/scan_inventory_test.exs`, `test/bolognesa/playback/`, `test/bolognesa/music/`, and movie/series/music LiveView and media controller tests. Detailed task commands must track their destination paths as tests move.

## Final commonality review

The implemented owners have independent facades, domain models, DTOs, tables, providers, transactions, and recovery processes. Movie-only metadata/correction changes stay in Movies; hierarchy/selection changes stay in Series; Music retains its existing import model. Shared global schemas do not grant cross-owner writes. Exclusive response DTOs live beside their use cases; the Series review item remains shared between list and single-item reads.

| Candidate and actual consumers | Common meaning and reasons to change | Dependency and decision |
| --- | --- | --- |
| `Movies.Infrastructure.Providers.TmdbClient` and `Series.Infrastructure.Providers.TmdbClient`, consumed by the respective TMDb providers | Authentication, five-second timeout, one-MiB response limit, and HTTP error classification coincide. Endpoints, payload parsing, candidate meaning, and owner error contracts can evolve independently. | Keep the two small transports local for this change. A later shared HTTP client could reduce duplicated technical policy, but would add a shared change point. If extracted, both providers would depend on neutral infrastructure with owner-independent errors, never on each other or a central identification service. No business context is justified. |
| `Movies.Domain.Entities.Identification` and `Series.Domain.Entities.Identification` | Manual precedence and stale-token protection coincide; scalar movie choices and ordered, bounded episode selections have different meanings and policies. | Keep local. Both application layers depend inward on their own decisions. Sharing would couple content invariants and weaken the ownership split. |
| Each owner's `EctoRequestWriter`, `EctoOutboxRepository`, `DecisionStore`, `JobRecovery`, dispatcher, worker, and reconciler | At-least-once delivery, locks, job linking, and bounded recovery are common mechanisms. The decision schemas, worker names, foreign-type filters, association handling, and terminal policies remain owner responsibilities. | Keep local. A shared orchestrator would recreate central Identification ownership and force schema/policy coupling. Extract a smaller mechanism only when a concrete change can remain independent of these rules. |
| `Libraries.Infrastructure.Repositories.EctoScanRepository` calling `Movies.request_batch_in_transaction!/2` or `Series.request_batch_in_transaction!/2` | The physical inventory request shape is the same; destination ownership is explicit and Music uses its existing inspection handoff. | Retain explicit type routing inside the inventory transaction and validation in both owners. A generic workflow would hide the atomicity boundary without reducing domain coupling. |
| `Playback.Infrastructure.Repositories.EctoPlaybackRepository`, `ContentRef`, `Source`, and `TranscodeSession`, consumed by direct/HLS controllers and detail playback helpers | Authorization, physical source selection, range delivery, temporary sessions, and revision checks have the same playback meaning across video kinds. Music keeps its separate selector. | Retain Playback ownership and typed references. Read joins project owner tables without importing their domain internals or writing their data. No new cross-content projection is warranted by current screens. |

No new business context, generic workflow, repository framework, or cross-content entity is warranted. A technical extraction remains possible when it has a concrete consumer benefit. Automated acceptance and fresh review are recorded separately in project status.

## Verification and documentation

The owner split passed the complete local suite and a fresh whole-change review. The review exposed merged-query-parameter ambiguity in HLS routing; manifest and segment tests reproduced the bypass, and controllers now construct content identity exclusively from route path parameters. Public playback helpers use the typed reference contract. Source ownership and independent-ID cleanup assertions were reviewed alongside transactional and recovery coverage.

The backend convention describes current responsibilities. Decisions 0005, 0010, 0012, 0013, and 0018 retain their still-valid matching, consistency, and recovery rules with links clarifying superseded ownership. Current automated, browser, and deployment evidence belongs in [project status](../status.md). Completed temporary implementation notes have been removed.

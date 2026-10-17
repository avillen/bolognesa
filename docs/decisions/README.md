# Architecture decisions

[Conventions](../conventions/backend.md) describe current rules. These records explain significant choices and their accepted costs. When a decision changes, mark the old record as superseded and link the replacement; update the current convention too.

| Record | Status | Decision |
| --- | --- | --- |
| [0001](0001-architecture-foundation.md) | Accepted | One Phoenix application, bounded contexts, domain independent of Ecto |
| [0002](0002-initial-access.md) | Accepted | One-time administrator setup and revocable sessions |
| [0003](0003-recoverable-library-scans.md) | Accepted | Durable PostgreSQL-backed scans with per-attempt generations |
| [0004](0004-technical-media-inspection.md) | Accepted | Durable revision-based inspection through an outbox |
| [0005](0005-catalog-identification.md) | Partially superseded by 0012 and 0019 | TMDb matching, review, and protected manual correction |
| [0006](0006-authorized-direct-playback.md) | Accepted | Reauthorized direct delivery with descriptor validation and byte ranges |
| [0007](0007-project-owned-documentation.md) | Accepted; refined for public use | Documentation organized by purpose and maintained in English |
| [0008](0008-global-persistence-schemas.md) | Accepted | Shared Ecto schemas in a global persistence namespace |
| [0009](0009-domain-results-from-repositories.md) | Accepted | Domain models returned from repositories |
| [0010](0010-context-owned-models.md) | Accepted | Each context owns its models and read projections |
| [0011](0011-live-transcoding.md) | Implemented | Optional FFmpeg/HLS compatible playback |
| [0012](0012-catalog-entry-identity.md) | Ownership superseded by 0019 | Shared catalog identity and atomic identification writes |
| [0013](0013-series-and-multiple-episode-associations.md) | Implemented locally | Series hierarchy and ordered multi-episode file associations |
| [0014](0014-parallel-port-infrastructure-categories.md) | Implemented locally | Parallel categories for ports and adapters |
| [0015](0015-domain-concept-directories.md) | Implemented | Domain directories by concept type |
| [0016](0016-user-locale-and-settings.md) | Implemented | Per-account language preference and settings |
| [0017](0017-generic-linux-compose-deployment.md) | Implemented | Configurable generic Linux Compose deployment |
| [0018](0018-local-music-catalog.md) | Implemented | Local music identity, durable inspection handoff, and direct audio |
| [0019](0019-content-context-boundaries.md) | Implemented and reviewed | Content-owned Movies, Series, and Music contexts with a clean database rebuild |
| [0020](0020-direct-durable-jobs.md) | Implemented locally | Atomic request/job creation without intermediate inspection, Music or video outboxes |

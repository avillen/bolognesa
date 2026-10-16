# 0005. Movie catalog and TMDb identification

Status: Partially superseded by [0012](0012-catalog-entry-identity.md). Provider, review, and stale-result rules remain in effect.

Ownership and identity are now governed by [0019](0019-content-context-boundaries.md); provider privacy, review, manual precedence, and atomic request rules remain valid.

## Context

The inventory records physical files but not the works they contain. Identification must group versions of one movie and allow manual corrections to survive scans and old jobs.

## Decision

- Movies have an internal identity and a unique `(provider, provider_id)` reference. Identification owns each file-to-work decision, its state, provenance, observed revision, and request token.
- The provider receives only a title inferred from the basename and an inferred year; it never receives local paths or library names. Use a runtime TMDb read token. Without one, work ends in a visible `not_configured` state.
- Accept the first valid candidate automatically; mark title or year discrepancies for review. Users can choose another result or leave a file unidentified.
- Before applying an automatic result, check token, revision, availability, and decision origin under lock. A manual correction gets a new token and takes precedence over retries and stale responses.
- Keep external HTTP requests outside transactions. Commit identification requests and their outbox events atomically with inventory batches.
- Identification controls the atomic association write. The later [decision 0012](0012-catalog-entry-identity.md) replaces this record's original cross-context write exception and identity details.

## Consequences

Automatic matching reduces setup effort but can select the wrong work; review and manual correction are required parts of the workflow. Sending inferred titles to TMDb discloses part of local filenames. TMDb artwork is fetched by the browser over HTTPS and may disclose the client's IP and image identifier to TMDb. A fallback image is shown when artwork is unavailable.

See the [TMDb attribution FAQ](https://developer.themoviedb.org/docs/faq) and [logo guidelines](https://www.themoviedb.org/about/logos-attribution).

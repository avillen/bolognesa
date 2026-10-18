# 0013. Series and multiple episode associations per file

Status: Accepted and implemented locally. Deployment and real-device verification are separate.

[0019](0019-content-context-boundaries.md) supersedes shared catalog identities and central Identification ownership with independent Series tables and ordered episode associations. Hierarchy, specials, complete bounded selections, matching, and whole-file playback rules remain valid.

## Context

The catalog needs series, seasons, episodes, specials, and support for a physical file containing several episodes. A single file-to-work reference cannot represent this without confusing the work with its physical source.

## Decision

Libraries have an immutable `movie` or `series` type; existing libraries migrate as movies. Catalog entries represent movies, series, seasons, and episodes. Each season belongs to a series; each episode belongs to a season. Season zero represents specials, and episode numbers are positive.

Each file has one identification decision and may have an ordered set of confirmed entries. A movie selects one work. A series file selects one to one hundred unique episodes from a single season. Validate and replace the complete set in one transaction; incomplete provider responses never confirm a subset. Manual corrections replace the full set and remain protected from stale automatic work.

Automatic matching requires an unambiguous normalized title and explicit year. Ambiguous names, missing episodes, or unclear numbering require review. Playback is available for confirmed movies and episodes, not series or season containers. A multi-episode file plays from the beginning in full with a visible notice; it is not cut into separate files. On completion, automatic continuation skips every episode associated with that file and selects the next available episode of the same series in season/episode order, crossing seasons when needed. Season zero follows the same numeric ordering; completion never loops back to earlier seasons. Missing versions are skipped, and the final available episode stops playback.

## Migration and consequences

Preserve prior movie IDs and confirmed associations. Rollback must reject series libraries, series identities, and multi-association decisions before removing data; never silently convert series to movies or collapse associations. Schema and code changes require coordinated activation.

The model adds joins and requires atomic replacement of associations. It does not implement file cutting, absolute numbering, or date-based identification. Automated checks do not verify deployment, device compatibility, or NAS performance.

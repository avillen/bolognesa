# 0025. Consecutive physical parts of an episode

Status: Implemented locally; deployment and real-device verification are separate.

## Context

A release can split one provider episode across several files. Treating those files
as interchangeable full versions loses their order. Creating another provider episode
would assign incorrect titles and shift the rest of the season's numbering.

## Decision

Keep the TMDb episode identity and metadata. A series file decision may have an optional
part number from 1 to 100, parsed from a case-insensitive `-partN` suffix immediately
after its single episode marker. For example, `Example S01E01-part1.mp4` and
`Example S01E01-part2.mp4` share episode 1. Tagged multi-episode selections and malformed
part names require review; manual correction preserves a valid filename part and rejects
incompatible selections. Unconfirmed decisions carry no active part.

The season lists each distinct part as an entry, retaining the episode's provider number
and adding a localized part label. Page totals count entries; catalog episode counts
remain distinct provider episodes. Files sharing a part number are versions of that
part. An untagged whole-episode file remains an alternative in playback options and
does not add a season card when numbered parts exist.

Episode URLs use `part=N` to select a part. With no explicit part, select an available
whole-episode version when one exists, otherwise the first numbered part. An invalid
or unavailable explicit part never silently selects another file. Manual navigation
includes parts and known unavailable entries in the current season. Automatic continuation
uses the completed file's persisted association: next consecutive part, then next available
episode across seasons. A known unavailable part or numbering gap stops continuation with
feedback. A whole-file alternative and an existing multi-episode file retain their
whole-file continuation rules. Every source is authorized again by Playback.

Part count is not external metadata: the application cannot infer an unobserved trailing
part from a filename without an explicit total. The existing file-scoped same-tab recovery
does not carry a position from one part into another.

## Activation and consequences

Original media remains read-only. Operators can rename files outside the application to
match provider numbering, then scan and identify them. A renamed path is a new inventory
entry. Previously confirmed `-partN` files need an identification retry, or re-saving
their manual correction, to adopt part semantics. The schema migration does not reinterpret
existing decisions or change their metadata associations. New scans preserve manual choices.

The additive migration preserves existing identities. Rolling it back is refused while
numbered-part decisions exist, because the preceding schema cannot preserve their meaning.
This extends the whole-file rules in [0013](0013-series-and-multiple-episode-associations.md)
and the Series ownership in [0019](0019-content-context-boundaries.md).

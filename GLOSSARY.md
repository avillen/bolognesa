# Glossary

Domain terms with a precise meaning in Bolognesa. Use them as defined in code, issues, and documentation.

## Catalog

**Catalog**: the movies, series, seasons and episodes Bolognesa keeps because at least one file is identified with them. Anything no file is identified with any more is dropped.

**Provider metadata**: what an external provider reports about a movie, series, season or episode, known only by the provider's identifier and not yet part of the catalog. A season's provider metadata lists all its episodes, including those no file matches. _Avoid_: details.

## Playback

**Playback attempt**: one browser's try at playing a video file, from version selection until it is ready, fails, or ends. It owns the probe, delivery plan, temporary transcode session, and a single recovery to a compatible plan. Events that do not belong to the current attempt are ignored. _Avoid_: playback session (that is the server-side transcode session), playback state.

## Series

**Episode**: a provider catalog episode of a season, identified by its season and number. _Avoid_: entry (when you mean the catalog episode).

**Part**: one explicitly numbered physical piece of a single episode, from 1 to 100. _Avoid_: segment, chapter.

**Entry**: one item in a season list: a provider episode, or one numbered part of it when the episode is split across files. Known unavailable entries are still entries. Several physical sources can represent the same entry. _Avoid_: season entry, episode target, episode card, file, version.

**Version**: a file that plays an entry. A whole-episode file of a split episode is a version, not an extra entry. _Avoid_: copy, file (when you mean its role in the catalog).

**Watched entry**: an account's recorded latest watched date for one entry, identified by catalog episode and optional part number. It records neither a viewing history nor a watch count, and does not prove that every moment was played.

**Adjacent entry**: the entry just before or after another in the same season, whether or not it is available. _Avoid_: episode target, neighbor episode.

**Next entry**: the entry automatic continuation opens after a played entry ends: its next part, or the first entry of the next available episode across seasons. _Avoid_: next episode, auto-advance target.

**Continue target**: the entry a series page offers to open for an account. Start at the first regular entry when nothing is watched; otherwise the entry after the most recently watched one (ties go to the furthest in season and part order), even if it is unavailable. Specials (season 0) are not part of the order. _Avoid_: resume position, next episode.

**Replay**: the Continue target when no available entry follows the most recently watched one: it restarts at the first regular entry.

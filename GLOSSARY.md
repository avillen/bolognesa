# Glossary

Domain terms with a precise meaning in Bolognesa. Use them as defined in code, issues, and documentation.

## Playback

**Playback attempt**: one browser's try at playing a video file, from version selection until it is ready, fails, or ends. It owns the probe, delivery plan, temporary transcode session, and a single recovery to a compatible plan. Events that do not belong to the current attempt are ignored. _Avoid_: playback session (that is the server-side transcode session), playback state.

## Series

**Season entry**: one item in a season list: a provider episode, or one numbered part of it when the episode is split across files. Known unavailable entries are still entries. Several physical sources can represent the same entry. _Avoid_: episode card, file, version.

**Watched entry**: an account's recorded latest watched date for one season entry, identified by catalog episode and optional part number. It records neither a viewing history nor a watch count, and does not prove that every moment was played.

**Continue target**: the season entry a series page offers to open for an account. Start at the first regular entry when nothing is watched; otherwise the entry after the most recently watched one (ties go to the furthest in season and part order), even if it is unavailable. Specials (season 0) are not part of the order. _Avoid_: resume position, next episode.

**Replay**: the Continue target when no available entry follows the most recently watched one: it restarts at the first regular entry.

# 0027. Document-owned persistent music playback

Status: Implemented locally; target-device checks pending.

## Context

The Music LiveView previously owned the audio element and album queue. Navigating to another screen destroyed that owner and ended playback. A persistent player needs document lifetime while selection and queue authorization remain server owned.

## Decision

- One authenticated root-layout host and audio element own playback state per browser tab. A JavaScript session and in-memory album queue survive authenticated LiveView navigation and temporary socket disconnection.
- Music screen hooks issue commands and subscribe to snapshots; unmounting only detaches screen listeners. Album progression requests authorization for each track from the server. The browser never constructs a guessed media URL or treats client state as authorization.
- Full document reloads, language changes that reload the document, and logout clear playback. Queue state is not persisted across tabs or devices.
- A `playing` event coordinates video and music: the other medium pauses, and neither automatically resumes. Autoplay failures and unavailable queue entries remain visible and require user action.
- Automated and browser checks cover the synthetic supported scenarios. Desktop Chromium at a narrow viewport does not establish real mobile device compatibility; keep the related work open until target-device checks are recorded.

## Consequences

The player host is independent of routed LiveViews, while the server continues to authorize selected tracks and deliver direct audio. The session is intentionally ephemeral and does not add a background process or browser storage. See [browser verification commands](../playback-testing.md#browser-player-verification).

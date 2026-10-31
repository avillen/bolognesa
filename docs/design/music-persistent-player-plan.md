# Persistent music player implementation plan

Status: Implemented locally; acceptance remains open pending the verification gates below. Implements [issue #16](https://github.com/avillen/bolognesa/issues/16).

## Agreed behavior

Music continues during authenticated application navigation and temporary LiveView socket disconnection. One audio element owns the current track, position and play/pause state per browser tab. The album queue continues outside Music. A global compact player exposes track, artist, artwork fallback, progress and essential controls, with the existing expanded presentation available.

Full document reloads, including the current language-change flow, end playback. Reload recovery, cross-device state, offline playback, queue editing, artwork import and a player-stack rewrite are excluded. Logout ends playback. Starting video pauses music; starting music pauses video. Neither player automatically resumes when the other stops.

## Approved architecture

Use a document-scoped JavaScript music session and an audio host rendered in the root layout, outside the replaceable routed LiveView. Initialize it once from `assets/js/app.js`; do not attach its lifetime to the Music hook. Keep immediate playback and the bounded queue in memory, without browser storage or a new server process. Screen hooks publish commands and subscribe to session snapshots; detaching a screen removes its subscriptions, never the audio element.

Keep authorization on the server. Add authenticated JSON operations for selecting a track and obtaining an album queue, using the existing `Playback.start_track/3` and `Music.album_queue/3` facades. Protect POST operations with the existing browser session and CSRF pipeline. Reauthorize each queue selection and retain authorization in the media controller. Browser state is never evidence of access. Do not expose filesystem paths.

This architecture is approved for implementation. The root-host probe described under Planning verification has passed; verify the implemented host again through real LiveView navigation. A shared function layout or `phx-update="ignore"` inside a replaced LiveView does not provide that guarantee.

Use monotonically increasing request generations: new selection invalidates outstanding queue/selection responses and stale media callbacks. Reconnection does not reload the source or replay an old play request. A disconnected socket does not block authorized HTTP queue progression while HTTP remains available. On HTTP failure, stop automatic progression and offer an explicit retry; never silently skip unavailable tracks. Authentication failure clears the session and source.

## Existing code and constraints

- `Music.Index.Live` currently owns selection, queue, generations and error feedback.
- `reducer/play.ex` and `reducer/album_playback.ex` already authorize selection and enforce queue behavior; preserve their observable rules while moving ownership.
- `audio_player.js` currently clears audio in `destroyed`; `audio_track_list.js` searches relative to the Music player frame. Both assumptions must change.
- Reuse the existing Video.js audio skin, CSS tokens, compact/expanded presentation, English and Spanish catalogs and accessible controls.
- Retain the 500-track album bound, current ordering and unavailable-track behavior. No schema changes or new runtime dependencies are planned.
- Decision 0018 and README currently describe page-local playback and need updating with the final implementation.

## Implementation increments

Each increment starts with a relevant failing behavior test, implements the smallest change, runs its focused checks and forms a reviewable commit. Do not claim issue completion before all acceptance gates pass.

### 01 — Establish the document-owned session

Files: create `assets/js/music/music_session.mjs` and `assets/test/music_session_test.mjs`; modify `assets/js/app.js`, `assets/js/music/hooks/audio_player.js` and `lib/bolognesa_web/components/layouts/root.html.heex`.

- [ ] Define `createMusicSession({audio, transport})`, with `getSnapshot()`, `subscribe(listener)` returning an unsubscribe function, `selectTrack({trackId, fileId})`, `playAlbum({albumId, libraryId})`, `next()`, `previous()`, `play()`, `pause()`, `seek(seconds)` and `clear()`.
- [ ] Snapshot exposes selected track metadata, queue index/count, paused state, position, duration, loading and bounded error status. Keep the raw audio element private except to the existing skin adapter.
- [ ] Test that screen unsubscribe/resubscribe retains audio identity, source, position and pause state; duplicate bootstrap creates no second audio; explicit clear removes the source and listeners appropriately.
- [ ] Add an initially hidden, stable root host and initialize the session once per document. Adapt the current hook into a view adapter rather than a media owner.
- [ ] Prove continuous DOM connection through Music → Movies → Music in a real LiveView browser fixture before expanding the implementation.

### 02 — Move queue commands behind authorized HTTP operations

Files: create `lib/bolognesa_web/controllers/music_playback_controller.ex` and its controller test; modify `lib/bolognesa_web/router.ex`, `assets/js/music/music_session.mjs`, Music `live.ex`, `live.html.heex`, reducers `play.ex` and `album_playback.ex`, `assets/js/music/audio_track_list.js`, and existing Music LiveView/JS tests.

- [ ] Add `POST /music/playback/track` accepting track/file IDs and returning authorized source and public display metadata; add `POST /music/playback/album` accepting album/library IDs and returning the existing bounded queue projection. Reuse facades; obtain display metadata through a public authorized Music read rather than trusting screen labels.
- [ ] Pin response contracts in controller tests, including anonymous access, malformed IDs, unavailable tracks, oversized albums and CSRF behavior. Return stable error codes; translate them in the presentation layer.
- [ ] Implement session transport with CSRF token, credentials and request generations. Test rapid competing track/album requests, stale errors, repeated ended events, end of queue and unavailable entries with Next still available.
- [ ] Connect Music row/album actions to the shared session. Remove obsolete socket-owned playback state only once replacements pass. Rows subscribe when mounted and reconcile after stream changes; returning to Music reflects the active track without restarting it.
- [ ] Browser regression: play an album, leave Music, let the track finish, assert the next track starts; return through album/artist filters and assert state consistency. Also assert paused music stays paused through navigation.

### 03 — Render the global player

Files: create `lib/bolognesa_web/components/music_player.ex` and `assets/js/music/music_player_view.mjs`; modify root layout, Music template, `assets/js/music/hooks/audio_player.js`, `assets/css/music.css` and relevant Gettext catalogs.

- [ ] Extract and reuse the existing compact/expanded presentation. The root host owns one presentation and one audio element; Music no longer renders another player.
- [ ] Bind metadata, fallback artwork, progress, seek, play/pause and previous/next controls to the session. Disable invalid actions and show loading, autoplay rejection and recoverable errors globally.
- [ ] Preserve accessible names, keyboard control, focus trapping and restoration, Escape handling and background inert cleanup. If the initiating screen disappears, restore focus to a surviving global control.
- [ ] Test global visibility on Home, Libraries, Movies, Series, Settings and About, and that no active player appears before selection or on public authentication screens.

### 04 — Verify responsive presentation

Files: modify `assets/css/music.css`, `assets/css/app.css`, global player component and browser regression script.

- [ ] Reserve content space only while the player is visible; account for mobile navigation and safe-area insets.
- [ ] Verify narrow and wide viewports, long/missing metadata, expanded player scrolling, focus visibility and reduced motion. Ensure navigation and the last content action remain reachable.
- [ ] Record desktop and mobile viewport automation separately from a real mobile browser check. Keep the real-device acceptance gate pending until performed.

### 05 — Coordinate actual media playback

Files: create `assets/js/music/media_coordinator.mjs` and its JS test; modify music session and `assets/js/video/hooks/video_player.js`.

- [ ] Register/unregister media participants and pause the other participant when playback actually starts. Handle both user controls and automatic queue/video continuation.
- [ ] Test music → video, video → music, failed autoplay, repeated play events, video source replacement, hook teardown and no automatic resumption.
- [ ] Run existing video hook tests and browser playback checks, including episode continuation/fullscreen. Preserve video recovery and conversion behavior.

### 06 — Reconnection, evidence and documentation

Files: create `scripts/playback/verify-persistent-music.mjs`; extend synthetic fixture setup as needed; modify README, decision 0018 (or link its superseding record) and testing conventions with the final browser command.

- [ ] Use synthetic audio through the actual application. Assert continuous element identity and increasing playback time across navigation; count exactly one audio host and no duplicated event effects after repeated transitions.
- [ ] Disconnect/reconnect LiveView transport without reloading the document; assert source identity, position, pause state and queue consistency. Repeat while paused and during track completion. Distinguish socket loss from HTTP/media loss.
- [ ] Test HTTP loss at a queue boundary, explicit retry, stale requests after clear, and logout/session expiration. Do not promise seamless playback across a server restart or unavailable media network.
- [ ] Run `node --test assets/test/*.mjs`, focused controller/Music LiveView tests, the new browser scenario, existing video browser checks and `mix precommit`. Record exact commands and actual results; do not describe planned checks as passing.
- [ ] Record real desktop/mobile observations, remaining blockers and next steps in the issue or PR. Reference #16 from incremental PRs. No milestone is currently assigned.
- [ ] Update public playback limits, remove completed temporary planning notes or distill durable architecture into a decision. Close #16 only after its acceptance criteria and device-verification gate are met.

## Review gates

The highest-risk checks are continuous root-host attachment, advancement when no Music LiveView exists, stale asynchronous responses, unauthorized selections after session expiry, and focus/overlay cleanup when the underlying screen changes. Mock hook tests alone cannot establish continuity; real LiveView browser checks are required.

## Planning verification

Architectural probe passed with `bash scripts/screenshots/run-readme-screenshots.sh --verify-music-host` on 2026-10-31. The implemented browser scenario also passed: `bash scripts/screenshots/run-readme-screenshots.sh --verify-persistent-music`. It verifies actual host/source continuity through navigation, pause state, queue progression outside Music, socket reconnection, retry and unavailable-item handling, logout cleanup, keyboard expansion, and a 375px Chromium viewport. `bash scripts/screenshots/run-readme-screenshots.sh --verify-fullscreen` passed for video continuation/fullscreen. These checks use desktop Chromium and synthetic media; they do not establish real mobile compatibility. The browser scenario does not yet cover video/music mutual pausing or authentication expiry at a queue boundary.

## Implementation status (2026-10-31)

The global session, authorized playback endpoints, Music screen migration, global controls, media coordinator, translations, and documentation are implemented locally. `node --test assets/test/*.mjs` passed (53 tests); `mix precommit` passed (667 tests, 1 skipped); `mix esbuild bolognesa` and `git diff --check` passed. The plan is not fully complete: remaining acceptance includes real-device mobile verification and the browser scenarios for music/video mutual pausing and authentication expiry. Some detailed transport/session edge-case contracts in the test matrix also remain broader than the current automated coverage. Keep issue #16 open until these gates are recorded.

## Executor guide: read this before changing code

This section makes the earlier increments precise. Where an earlier sentence is ambiguous, use the contracts below. These are implementation instructions, not a claim that the feature already exists.

Work on the existing `music-persistent-player` branch and preserve uncommitted planning and probe changes. Do not create another worktree. Implement tasks in order; finish the focused verification for a task before removing the old behavior it replaces. Do not publish, deploy, merge, or close the issue as part of implementation.

Read `AGENTS.md`, `docs/conventions/{elixir,backend,frontend,phoenix,testing,observability,documentation}.md`, decisions 0018/0019/0024 and this whole plan. Inspect the current file before editing it; paths and selectors below describe the code inspected during planning and may have changed. Keep all public documentation and code comments in English. UI text uses Gettext with English and Spanish translations.

### Known baseline and ownership

The root-host architectural probe is already implemented in `scripts/playback/verify-music-host.mjs`, invoked with `bash scripts/screenshots/run-readme-screenshots.sh --verify-music-host`. It passed with actual authenticated LiveView navigation and synthetic data. Preserve it until the end-to-end product check supersedes it. It inserts a host dynamically: it proves that placement outside the routed LiveView works, but does not prove that the future HEEx component and bootstrap are correct.

| Responsibility | Final owner | Must not own it |
| --- | --- | --- |
| One audio element and source changes | Document-scoped music session | Music LiveView mount/destroy |
| Current time, actual pause state, duration | Native audio element, projected by session | Server assigns |
| Album queue and current index | Music session in memory | URL, local/session storage, database |
| Authorization and current track/file relationship | Playback facade and media delivery | Client metadata or IDs alone |
| Authorized public metadata | Music facade | Controller queries into schemas |
| Catalog loading/filtering/retry-import | Existing Music LiveView | Global player |
| Global player labels and structure | HEEx component using Gettext | Hard-coded English JS strings |
| Rendering dynamic player values | Document-scoped view adapter | LiveView DOM patches |
| Track-row indicators/actions | Screen hook subscribed to session | Global DOM observer over entire body |
| Audio/video exclusion | Document-scoped media coordinator | Cross-context backend services |

### Exact HTTP contracts

Create `MusicPlaybackController` with `track/2` and `album/2`. Use `BolognesaWeb, :controller`. Add routes in a separate scope using the existing `:browser` pipeline, so session fetching and CSRF protection run. Do not use `:authenticated` there: its redirect behavior is unsuitable for JSON. In the controller check `conn.assigns.current_scope` safely before extracting the actor; respond with JSON 401 when absent. Backend facades still authorize the actor and return forbidden for a signed-in non-admin. Do not change authentication behavior for existing HTML routes.

Requests use `Content-Type: application/json`, `Accept: application/json`, `X-CSRF-Token` from the existing meta tag, and `credentials: "same-origin"`. IDs are JSON positive safe integers, with optional `library_id: null`; reject strings, floats, negative/zero values, booleans, missing IDs, lists and values greater than JavaScript's `Number.MAX_SAFE_INTEGER`. Keep validation local and explicit; never create atoms from user input.

`POST /music/playback/track` body: `{"track_id": 12, "file_id": 34}`. Success status 200:

```json
{"track":{"id":12,"file_id":34,"title":"Example","artist":null,"album":null,"duration_ms":10000,"state":"ready"},"src":"/music/tracks/12/media/34"}
```

The source is constructed with a verified local route after `Playback.start_track(actor, track_id, file_id)` succeeds; do not serialize its `Source` struct. It contains internal delivery data including paths. Obtain display data using the new authorized `Music.fetch_track/2` described below. Verify its file ID equals the requested file ID. A successful selection response does not replace authorization when the audio later requests the media URL.

`POST /music/playback/album` body: `{"album_id": 56, "library_id": null}`. Success status 200: `{"tracks":[<track projection above>]}`. Call `Music.album_queue/3` and map only the listed public fields explicitly. A pending/failed entry may have `id: null`; keep it in the queue, including its positive `file_id`, title and state. Do not filter it or invent an ID. There is no source URL in the album response. An empty returned list is valid and must not replace or interrupt the existing session; show an `empty_queue` error.

Every error body is `{"error":{"code":"<allowlisted-code>"}}`. Map absent session → 401 `unauthenticated`; facade `:forbidden` → 403 `forbidden`; invalid input or `:invalid_query` → 400 `invalid_request`; `:not_found`/`:missing` → 404 `not_found`; `:album_too_large` → 422 `album_too_large`; `:unavailable` → 503 `unavailable`. Log unexpected failures through the established error handling; do not return exception details. CSRF failures may be framework-generated non-JSON responses; transport must handle them without parsing HTML as JSON.

### Missing Music read: implement explicitly

There is currently no `Music.fetch_track/2`. Do not search list pages to find a track and do not query schemas in the controller.

1. Add `fetch_track(track_id)` callback to `Music.Application.Ports.Readers.TracksReader`, returning `{:ok, TrackRow.t()} | {:error, :not_found | :unavailable}`.
2. Implement it on `EctoTracksReader` using the existing `base_query(nil)` availability filters, join bindings, projection tuple and `row/1` mapping. Filter the track binding by exact ID, limit to one row and return `:not_found` if absent. Reuse the existing projection by extracting a small private helper if needed; do not rewrite list ordering/pagination.
3. Add `Music.Application.UseCases.FetchTrack.call(actor, track_id, reader)`: authorize `:admin`, validate a positive integer, invoke the reader and return `Track.from_domain(row)`. Invalid ID returns `:not_found`; forbidden is preserved.
4. Expose `Music.fetch_track(actor, track_id)` using `EctoTracksReader` and the normal typed facade style.
5. Update any test reader implementing the behaviour, including `test/support/music/stale_count_tracks_reader.ex`; inspect all `@behaviour ...TracksReader` occurrences first.
6. Tests: ready track projection; anonymous/non-admin forbidden; absent/unavailable file excluded; invalid ID; controller rejects a valid track paired with another file; no absolute/relative source paths appear in JSON. Use existing music fixtures rather than a new fixture framework.

### JavaScript modules and transport boundary

Create `assets/js/music/music_transport.mjs` exporting `createMusicTransport({fetch, csrfToken})`. Its methods are `selectTrack({trackId, fileId}, {signal})` and `loadAlbum({albumId, libraryId}, {signal})`. Resolve parsed success bodies, or throw an Error with a bounded `code` property. Treat non-JSON/redirected responses as failure; never navigate to a login HTML response. A 401 or redirect to login yields `unauthenticated`, 403 yields `forbidden`, unrecognized response/network/JSON errors yield `unavailable`. Abort errors remain distinguishable and never appear as visible playback failures. Validate minimal response shape and a maximum queue length of 500 before accepting it. Accept source URLs only as the expected local music media route for the returned/requested IDs.

Create `assets/js/music/music_session.mjs` exporting `createMusicSession({audio, transport})`. For tests, inject an EventTarget-like fake audio and deferred transport promises; never require a real socket or timers to test request races.

`getSnapshot()` returns a fresh read-only projection (copy arrays/objects or freeze immutable state):

```js
{
  selected: null, // or {id, file_id, title, artist, album, duration_ms, state}
  queue: [], // copied public projections, max 500
  queueIndex: -1, // attempted item, even when that item cannot play
  queueCount: 0,
  paused: true, position: 0, duration: null,
  loading: false, finished: false,
  error: null // or {code, retryable}
}
```

Expose `subscribe(listener)` (immediate snapshot, returns unsubscribe), `getSnapshot()`, `selectTrack({trackId,fileId})`, `playAlbum({albumId,libraryId})`, `next()`, `previous()`, `play()`, `pause()`, `seek(seconds)`, `retry()`, `clear()` and `destroy()`. `clear` resets playback but retains subscriptions and native listeners; `destroy` calls clear and removes all listeners/subscriptions. A screen unmount calls only its unsubscribe, never either lifecycle method. Extend the earlier method list with retry/destroy as specified here.

Use two counters: command generation for pending HTTP operations and source generation for native media events/play promises. Every new selection, queue move, retry or clear invalidates older commands. Check equality after every await and in catch/finally before modifying state. Abort obsolete requests as an optimization; correctness must rely on generation checks even if the transport ignores abort.

### State transitions: implement and test these exact rules

| Trigger | Required transition |
| --- | --- |
| Individual selection starts | Mark loading; keep existing source playing until selection succeeds. Invalidate older pending commands. |
| Individual selection succeeds | Pause old source; replace queue with empty array/index -1; set metadata; set source once; call load once and request play once. Clear old error/finished. |
| Selection fails | Keep the previous selected track/source and queue. Show error without reloading. Authentication failure instead clears everything. |
| Album request starts | Keep existing playback until nonempty queue arrives. |
| Album request succeeds | Replace queue, index 0, then authorize/select the first item through track transport. Do not start from a guessed media URL. |
| Queue move starts | Pause/clear outgoing source; retain queue and set attempted index; authorize that item. If ID is null or state is not ready, fail locally as unavailable. |
| Queue item fails | selected null; paused; source removed; show error; retain attempted index and next/previous controls. No automatic skip. |
| Next on last item / Previous on first | No operation; controls disabled. |
| Current source ends with another queue item | Advance exactly once through authorized selection, even when Music is unmounted. |
| Current source ends on final item | finished true, paused true; retain final metadata and queue index; no out-of-bounds index or repeated requests. |
| Individual source ends | Remain on its metadata, paused; no queue request. |
| Repeated/stale ended callback | Ignore after source has already been consumed or replaced. Use a per-source consumed guard, not just a command counter. |
| `play()` rejects NotAllowedError | Preserve selection, show autoplay_blocked, leave manual Play enabled. Do not call load again. |
| Other current-source play/media error | Show playback_failed and leave retry/Next available; ignore AbortError and stale promises. |
| `pause()` | Pause immediately; native pause events update snapshot. Never send this to the server. |
| `seek(seconds)` | Ignore NaN/infinity or unknown/nonpositive duration; clamp to [0,duration]; assign currentTime without load. |
| `retry()` | Repeat the last failed operation only if still current. A failed queue item uses its attempted index. A playback failure reauthorizes the selected track before loading. |
| `clear()` | Invalidate commands, abort requests, pause/remove source/load once, reset state, notify subscribers. Late replies cannot resurrect playback. |
| Socket reconnect | No session command and no audio load/play. Screen subscribers simply read the current snapshot. |

Install native listeners once: loadedmetadata/durationchange, timeupdate, play/playing, pause, ended, error and emptied as needed. Compute actual pause state from the audio element. Render unknown duration safely and disable seeking until finite duration exists. Never infer that a fulfilled play request guarantees the element is still playing. On source replacement bind callbacks to the source generation and remove obsolete source listeners. Do not let errors caused by intentional source cleanup become visible failures.

### Root component and bootstrap wiring

Create `BolognesaWeb.MusicPlayer` in `components/music_player.ex`, using the project component conventions. Render `<MusicPlayer.host ... />` as a direct body child after `{@inner_content}` in root layout. Check `assigns[:current_scope]` defensively; render only for authenticated scope. Test both authenticated and public root responses to confirm the assign is available on initial requests. The component receives localized labels/errors, not a backend queue.

Use IDs `music-player-host`, `music-playback`, `music-player`, `now-playing`, `queue-previous`, `queue-next`, `queue-position`, `queue-finished`, and `audio-error` once each. Preserve existing selectors where they represent the same behavior. Initially the host is hidden and the audio has no source. Render the audio element once; use `audio.src` as the single source mechanism throughout the new implementation. Remove the old source-child-specific AudioError wiring from this path rather than maintaining two source mechanisms.

Create `assets/js/music/music_bootstrap.mjs` exporting `initializeMusicPlayer(document, dependencies)`. Cache the initialized instance on the host under a module-private Symbol; repeated calls return the same instance. If no authenticated host exists, return null. Initialize transport, session, view adapter and coordinator there. Import/call initialization in `app.js` before `liveSocket.connect()`. The static root host does not use a LiveView hook. Do not initialize again on phx:page-loading-stop.

The existing Video.js custom audio elements still need their vendor import. Move wrapping creation from AudioPlayer.mounted into bootstrap/view setup once: audio-player → audio-skin → the same audio node. Disable native controls only after the custom controls are installed. Existing Video.js controls act on the same audio and session observes its native events.

### Music screen migration and deletion checklist

Use `AudioPlayer` as the screen subscription hook (rename to MusicPlayback only if every import/test/HEEx reference is updated together). Mount it on an always-present, uniquely identified Music section, not on a conditionally selected player. It obtains the document session from bootstrap, subscribes to snapshots and delegates clicks from track/album buttons. Keep references on the hook so destroy removes every listener, observer and subscription.

Track buttons carry `data-track-id`, `data-file-id` and `data-music-action="track"`. Album button carries `data-album-id`, nullable library ID and `data-music-action="album"`. Validate DOM values as positive safe integers. Remove `phx-click="play"`/`play-album` from these buttons: one click must not dispatch both an HTTP operation and a LiveView playback event. Clicking the current track toggles pause/play without selecting/reloading it. A different track invokes selectTrack.

Adapt `audio_track_list.js` to accept the list and session rather than finding a list relative to the player frame. Match current rows by track/file identity, not title. Reconcile on session snapshots and stream mutations; teardown its MutationObserver. Keep its existing behavior tests and update their boundary.

After new behavior works, remove from `Music.Index.Live`: queue, queue_position, queue_loading?, queue_request, queue_finished?, player_generation, player_stopped?, play_requested?, selected, audio_error; playback-only event handlers; album_queue async handler; audio_feedback helper; Play/AlbumPlayback aliases. Remove the old player markup from Music template and playback-only queue/error UI there. Retain catalog request_id, error, loading, filters, streams and retry-import handlers. Remove page_tracks only if ApplyPage and all remaining code no longer need it. Delete Play and AlbumPlayback reducers after all references are removed. Delete AudioError only if no remaining code imports it; otherwise keep its existing contract for those callers.

Search all references to removed assigns/events before compiling. Existing LiveView tests asserting now-playing or render_hook(audio-ended) must migrate those playback assertions to session/browser tests. Keep LiveView assertions for catalog rendering, action data attributes, filters and import retry. Do not weaken coverage by deleting playback scenarios without equivalent tests at the new owner.

### Global view, accessibility and layout rules

`music_player_view.mjs` exports `connectMusicPlayerView(host, session)` returning `{destroy()}`. It subscribes once, updates text with textContent (never innerHTML), and delegates button actions using `data-player-action`. Translate error codes with hidden server-rendered message nodes or an explicit localized lookup serialized safely by HEEx. Never display raw network errors.

Host hidden iff selected is null, queue empty and there is no error/loading. Queue failure still exposes Next and its error. Show title fallback already provided by Music, optional artist, musical-note art fallback, elapsed/total time, seek and queue controls. Unknown duration displays a placeholder rather than NaN. Play/Pause accessible labels track actual state.

Reuse existing expanded behavior but move it to the persistent view adapter. Trap Tab/Shift+Tab among enabled focusable controls, Escape collapses, expand focuses Close, collapse restores Expand. Store and restore previous inert values. On phx:page-loading-start collapse the expanded view and restore inert before LiveView replaces the background; this avoids leaving new content inaccessible. Remove that listener on adapter destroy. Do not inert the audio host itself.

Use ResizeObserver on the visible compact player to set a body CSS variable for actual occupied height. Add bottom content padding equal to that height plus safe-area inset; remove it when hidden. Do not hard-code a height that clips wrapped labels. Check existing mobile navigation before selecting stacking order. Use 44px minimum control targets and no horizontal page overflow at 375px. Test 375×812 and 1440×900, long titles, no artist, error text and keyboard-expanded mode.

### Audio/video coordinator contract

`media_coordinator.mjs` exports `createMediaCoordinator()` with `register(mediaElement)` returning an unregister function. On native `playing`, pause every other registered media element whose paused flag is false. Ignore repeated events from the same participant; pause never causes resume. Use playing rather than attempted play, so blocked autoplay does not pause a currently playing participant.

Bootstrap registers the one music audio. VideoPlayer.mounted registers `this.video` using the shared coordinator; destroyed unregisters it before current cleanup. Keep the registration stable across VideoPlayer.updated source replacement. Coordinator operations do not change video URLs, hooks, recovery scopes, HLS sessions or fullscreen handling.

### Required tests, by owning layer

Use descriptive test names and behavior assertions. The following cases are required; several may share fixtures but not ambiguous assertions.

- Transport: CSRF/credentials, correct JSON bodies, ready/pending album decoding, 401/403 clear signal, malformed JSON, redirect, network failure, oversized response and invalid source URL.
- Session: initial state; immediate subscribe/unsubscribe; source load exactly once; paused navigation subscriber replacement; individual selection failure preserves old source; album replaces only after fetch; pending queue entry stops with Next available; next/previous boundaries; final completion; duplicate ended; competing album/track responses in both orders; stale error/finally ignored; late response after clear; blocked autoplay; seek validation; retry; auth failure; destroy cleanup.
- Bootstrap/view: duplicate initialization reuses the same instance/audio; no public host returns null; safe text rendering; global error visible; unknown duration; expanded keyboard focus and inert restoration; source never changes on view reattachment.
- Controller/use case: authorization, ID validation, exact public projection, mismatched file, missing/absent track, album ordering/boundary 500 vs 501, null-ID queue entry preserved and media route still reauthorizes independently.
- Screen integration: streamed row indicator updates, current row toggles without HTTP reselection, other row selects once, album sends correct library scope, destroy detaches subscriptions without pausing audio.
- Coordinator: both directions, repeated playing, blocked attempt, unregister and source replacement.

### End-to-end browser procedure

Extend the existing screenshot runner with `--verify-persistent-music`, following the established isolated PostgreSQL/browser/fixture cleanup pattern. Create `scripts/playback/verify-persistent-music.mjs`; do not point it at a personal media installation. Inspect `seed_readme_screenshots.exs` before adding fixtures. Generate a short synthetic playable audio fixture with FFmpeg or an existing fixture tool and seed at least two ordered album tracks plus an unavailable entry. Keep fixture duration long enough to test navigation without finishing accidentally.

1. Authenticate with the existing synthetic account and open Music. Assert one host, one music audio, hidden before selection.
2. Click a track and wait for native playing. Save the audio/host object references, current source and time; observe removals of the host or any ancestor.
3. Navigate using real `data-phx-link` links (catalog links include query strings), not page.goto. Visit Movies, Settings and Music; assert the same node remains connected, source unchanged and time increases. Use media events/waitForFunction, not arbitrary sleeps.
4. Pause, repeat navigation and assert position stable within a small stated tolerance and no play event.
5. Start an album, leave Music, allow the synthetic first track to finish naturally. Assert track two is authorized/loaded once and global metadata changes. Return to Music and assert matching row indicator.
6. Call the exposed `window.liveSocket.disconnect()` without reloading; wait for socket close; audio should continue. Reconnect with `connect()`, wait for phx-connected and assert no new source/load/play request. Repeat while paused and at a queue boundary.
7. Intercept the playback HTTP endpoint to fail at the next boundary. Verify visible error, retained queue index, usable Next/retry and no automatic skip. Restore the route and retry. Intercept a 401 separately and assert cleared source/queue.
8. Start actual video playback and assert music pauses; start music and assert video pauses. Verify no automatic resume on the other's pause.
9. Repeat key layout checks at the two specified viewport sizes, including reaching the final page action and expanding/collapsing with keyboard.
10. Log out and assert the old audio cannot remain active. Full reload/language-change recovery is intentionally not asserted.

Run the browser scenario against the implemented root host; do not inject a replacement host as the architectural probe does. Record passing assertions and limitations. A desktop Chromium mobile viewport is not evidence of real mobile browser compatibility.

### Commands and completion checklist

Focused commands (run after adding the named files):

```sh
node --test assets/test/music_session_test.mjs
node --test assets/test/*.mjs
mix test test/bolognesa_web/controllers/music_playback_controller_test.exs
mix test test/bolognesa_web/live/music/index/live_test.exs
mix test test/bolognesa/music
bash scripts/screenshots/run-readme-screenshots.sh --verify-music-host
bash scripts/screenshots/run-readme-screenshots.sh --verify-persistent-music
bash scripts/screenshots/run-readme-screenshots.sh --verify-fullscreen
mix precommit
git diff --check
```

Use the existing documented synthetic MP4/HLS fixture command with `npm run test-video-player -- tmp/videojs-fixtures` when touching video integration. If a command fails, capture the actual failure, fix its cause and rerun that check. Do not replace assertions with weaker ones to get a pass. Documentation-only plan updates do not require running the implementation suite.

- [ ] Update this plan's checkboxes only after the corresponding behavior is implemented and verified.
- [x] Update README playback limits and testing guide with actual behavior and commands.
- [x] Add a durable decision for document-owned music playback and mark only the conflicting page-lifecycle paragraphs of 0018 superseded; preserve its catalog/import decisions.
- [ ] Inspect diff for unused reducers, stale imports/assigns, duplicate IDs/listeners, untranslated text, private paths and unrelated changes.
- [x] Run final required checks after the last product change. Record evidence and pending real-device checks in the relevant issue/PR when writing there is authorized; otherwise provide the prepared evidence to the user.
- [x] Keep #16 open if actual mobile-device verification remains pending. Report exactly what is implemented, what was tested and what remains.

If interrupted, report the branch, changed files, last passing/failing command and next concrete step. Do not describe the entire feature as complete merely because the host probe or unit tests passed.

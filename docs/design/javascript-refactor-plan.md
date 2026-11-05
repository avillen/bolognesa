# Browser JavaScript architecture and refactor proposal

Status: proposed; implementation has not started.

**Goal:** make playback changes understandable by reducing long functions, nested branching, implicit contracts, and interleaved asynchronous operations while preserving current behavior.

**Architecture:** retain context ownership under `music/`, `video/`, and `shared/`. Use thin LiveView hooks, explicit session/controller APIs, focused browser adapters, and pure functions for decisions that do not require browser effects. Keep one owner for each mutable state and resource.

**Stack:** existing JavaScript ES modules, Phoenix LiveView, Video.js, hls.js, Node tests, and Playwright. No framework or dependency migration is proposed.

**Basis:** [frontend](../conventions/frontend.md), [Phoenix](../conventions/phoenix.md), [testing](../conventions/testing.md), [recovery decision 0024](../decisions/0024-tab-playback-recovery.md), and [persistent music decision 0027](../decisions/0027-persistent-music-player.md).

## Diagnosis

The inspected tree contains 24 application JavaScript files and 2,074 lines. Its context boundaries are already useful; directory layout is not the main problem.

- `music/music_bootstrap/session.mjs` has 573 lines. `createMusicSession` combines queue progression, authorization, source replacement, asynchronous command invalidation, retry, activity reporting, subscriptions, and media effects. Extracted queue, command, and activity helpers already provide a starting point.
- The session publishes 13 equivalent album-start aliases and a `Proxy` that interprets any unknown property containing `play` as an album-start command. `playAlbumAt` also accepts several alternative input shapes. This makes callers and mistakes difficult to identify. The screen hook uses a chain of fallback method names.
- `music/hooks/audio_player.js` mixes dataset parsing, action dispatch, playback decisions, menu dismissal, feedback timers, and activity notifications inside hook lifecycle callbacks. `music_bootstrap/player_view.mjs` combines rendering, command binding, queue visibility, modal focus, and background inertness.
- `video/hooks/video_player.js` builds controls and feedback, manages fullscreen, chooses sources, and coordinates recovery and diagnostics. Its `sync` closure performs several kinds of transition. Internal direct/HLS controllers imitate hooks through `.call(context)`, with an implicit mutable context contract.
- Music and video coordinate through `window.bolognesaMusicPlayer`; the medium-neutral coordinator is stored under music. Some tests load source strings through data URLs, and the HLS test replaces an import as text. Node reports a module-type warning for mixed `.js`/`.mjs` imports.
- `mix precommit` runs Elixir checks and ExUnit, but does not run the Node suite. The existing `video` job in `.github/workflows/screenshots.yml` already runs Node and synthetic video checks for matching changes. A passing local precommit alone cannot validate a JavaScript refactor.

This inspection does not establish playback defects, memory leaks, or device compatibility. Existing tests already protect important queue races and playback behavior.

One code-level follow-up needs separate characterization: when an album starts at a later track and first-track authorization fails, `replacementAlbum` retains only album/library IDs, so retry can lose the requested starting track/index. This was identified by reading the failure path, not reproduced in a browser. Confirm it with a focused regression and track any fix separately; the API cleanup must not silently change retry behavior.

## Design and constraints

The proposed decisions below are recommendations for review, not accepted project conventions yet.

1. Hooks adapt LiveView lifecycle and events; sessions coordinate use cases; views render snapshots and bind local controls. Helpers should own a coherent decision or resource rather than an arbitrary slice of lines.
2. Use guard clauses for invalid input and inactive/stale operations. Dispatch independent commands through named handlers instead of a growing nested action chain. Keep ordered source transitions explicit; do not flatten them at the expense of correctness.
3. Use ordinary objects with documented methods. Prefer one canonical input shape and remove speculative compatibility aliases after checking all consumers. Use concise JSDoc for session, snapshot, transport, and controller contracts; do not introduce a parallel type model for all backend data.
4. Keep the session as the single owner of selected track, queue, retry operation, and operation generations. Media position, duration, and paused status remain browser-owned; avoid independently mutable copies where they are not needed for transitions.
5. Resources have explicit teardown: views unsubscribe, controllers remove listeners and destroy HLS, and session destruction invalidates pending work. Navigation only detaches the Music screen; it must not destroy document-owned playback.
6. Preserve authorization per track, request order, duplicate queue-entry identity, autoplay errors, explicit retry, listening thresholds, localization, recovery scope, and fullscreen element identity. Preserve original units and LiveView event names/payloads.
7. Retain the existing browser build target and native HLS fallback. No TypeScript conversion, generic state-machine framework, event bus, base-player hierarchy, backend redesign, or product changes in this work.

Candidate layout: retain `music/music_bootstrap.mjs` as the composition entry; move its implementation to `music/player/` when the responsibility changes. That directory owns `session.mjs`, `queue.mjs`, `commands.mjs`, `listening_activity.mjs`, `media_events.mjs`, `media_session.mjs`, `player_view.mjs`, `queue_view.mjs`, and a focused `player_dialog.mjs`. Keep `music/music_transport.mjs` and screen-specific helpers beside `music/hooks/audio_player.js`. Put the medium-neutral coordinator in `shared/media_coordinator.mjs`. Video implementation remains beside its hook in `video/hooks/video_player/` with explicit `direct_controller.mjs`, `hls_controller.mjs`, and `source_controller.mjs` boundaries. Avoid a separate rename-only project; make these moves with their owning task and update imports and tests together.

## Incremental implementation plan

Execute one bounded task at a time with `superpowers:executing-plans`. Existing tests are the refactor safety net; add behavioral coverage for gaps before changing those paths. Each task should be independently reviewable and leave a working application. Do not combine the entire plan into one rewrite.

### 1. Close the music command contract

**Files:** `music_bootstrap/session.mjs`, `hooks/audio_player.js`, their existing tests, and new `assets/test/music_session_contract_test.mjs` (paths relative to `assets/js/music/` unless otherwise specified).

**Interface:** retain `playAlbum({albumId, libraryId = null, trackId = null, fileId = null, startIndex = null})` as the canonical album-start method; retain the existing named queue/transport controls. `subscribe(listener)` returns an unsubscribe function and `getSnapshot()` returns detached display data. Preserve existing command result/error semantics during this task.

- [ ] Inventory callers in application code, templates, tests, and verification scripts. Add coverage for successful album starts at a specified track/file and index, the existing retry behavior, and unknown methods remaining undefined. Characterize the potential retry-selection defect above and record it separately before deciding whether to schedule a fix.
- [ ] Replace the hook's fallback chain with `session.playAlbum(...)`; remove the aliases, dynamic `Proxy`, and unused input synonyms after migrating consumers. Add JSDoc for the canonical command inputs and snapshot.
- [ ] Run the contract, audio hook, session, queue, transport, and bootstrap tests; then the full Node suite. Review for behavior changes concealed by API cleanup.

**Acceptance:** every supported command can be found by its declared method name; an unknown play-like method does not silently start playback; album selection, retries, and queue behavior retain their verified semantics.

### 2. Simplify screen actions and player presentation

**Files:** `hooks/audio_player.js`, `hooks/audio_player/track_list.js`, new `hooks/audio_player/actions.mjs`; `music_bootstrap/player_view.mjs` moves to `player/player_view.mjs`, with new `player/player_dialog.mjs`; update bootstrap imports. Move `queue_view.mjs` alongside its view.

**Interfaces:** `parseMusicAction(button)` returns a validated `{type, ...canonicalIds}` or `null`; `executeMusicAction(session, command)` invokes a declared session method. `connectPlayerDialog(host)` returns `{expand(), collapse(restoreFocus), destroy()}`. The view owns its local expanded/queue-open state; these do not become playback-session state.

- [ ] Extend `audio_player_test.mjs` to cover invalid/missing IDs, track-only versus album-start behavior, and toggling the currently selected track. Add focused tests for dialog focus return and restoration of pre-existing inertness on destruction.
- [ ] Extract parsing and named action handlers; keep menu effects and feedback in the screen adapter. Extract dialog lifecycle from the view; split the snapshot callback into named rendering operations without adding duplicate subscriptions.
- [ ] Preserve existing accessible labels, Escape handling, menu focus, feedback, stream row updates, and navigation collapse. Run relevant Node tests and the persistent-music browser workflow.

**Acceptance:** the click listener reads as parse → dispatch → feedback; snapshot rendering does not manage modal lifecycle; screen teardown removes subscriptions and timers without stopping playback.

### 3. Separate music orchestration from media effects

**Files:** move `music_bootstrap/session.mjs` and its existing helpers into `player/`; add `player/audio_source.mjs` and `player/pending_operations.mjs`; update bootstrap and test imports.

**Interfaces:** session public methods remain those established in Task 1. `createAudioSource(audio)` owns source loading, play/pause/seek, clearing, and media teardown; it does not authorize tracks or mutate the queue. `createPendingOperations()` owns cancellation tokens, replacement completion, and append ordering; it does not own selected-track or queue state. Final helper signatures are an implementation choice, reviewed against these ownership constraints before extraction.

- [ ] Keep and run existing tests for ordered appends, FIFO play-next, replacement failure, deferred ended, queue duplicates, previous, clear, and stale responses. Add coverage for a late play rejection and a late authorization response after source replacement/destruction.
- [ ] Extract audio effects and pending-operation bookkeeping separately, preserving their ordering. Give successful selection, failed selection, and retry preparation named transitions; use guards for stale/destroyed operations. Keep related transition state together rather than scattering each counter across modules.
- [ ] Identify redundant snapshot fields separately from required transition flags; remove only fields whose consumers and semantics are covered. Preserve request generations even when abort is available, since cancellation alone does not establish response freshness.
- [ ] Run the session, listening activity, bootstrap, and full Node suites and the persistent-music browser workflow.

**Acceptance:** the session exposes understandable use cases rather than a single mixed lifecycle function; audio effects and concurrent-operation rules can be read and tested separately. Pending operations cannot resurrect a cleared/destroyed session or reorder additions.

### 4. Make video source controllers explicit

**Files:** `video/hooks/video_player.js` and `video/hooks/video_player/`; extend `assets/test/transcode_video_test.mjs`, recovery/diagnostic tests, and `scripts/playback/verify-video-player.mjs`.

**Interface:** factories `createDirectController({video, config, pushEvent, reportPlaybackError, onReady})` and `createHlsController({...same, Hls})` initialize the selected source and return `{update(config), destroy()}`. The hook supplies the production HLS dependency. A source coordinator owns active-controller replacement; the mounted frame and video element retain identity. Recovery/diagnostics remain separate collaborators with their existing behavior.

- [ ] Extend browser scenarios for same-signature updates, direct↔HLS replacement, error→retry, and teardown. Assert retained video/fullscreen identity and no events from the outgoing controller. Preserve tests for whole-file seek units and native HLS readiness.
- [ ] Replace internal hook-shaped controllers and `.call(context)` with the explicit factories. Extract source-change decisions from DOM feedback rendering, naming the phases: retain outgoing recovery → dispose source → configure media → attach controller. Keep recovery's ability to defer source attachment.
- [ ] Test the injected HLS boundary without rewriting import source. Run Node tests, `npm run test-video-player -- tmp/videojs-fixtures`, and the real LiveView fullscreen verification.

**Acceptance:** only the outer hook uses LiveView lifecycle methods; controller dependencies and teardown are explicit; source changes preserve recovery, global timeline, retry, and fullscreen behavior.

### 5. Clarify document composition and JavaScript verification

**Files:** `app.js`, `music/music_bootstrap.mjs`, coordinator moves to `shared/media_coordinator.mjs`; affected tests, `package.json`, CI configuration, and frontend/testing conventions.

**Interface:** a document-owned coordinator exists independently of the presence of the music host. A narrow runtime accessor exposes `{musicSession, mediaCoordinator}` to hooks, preserving the current null behavior on public pages. `app.js` wires it once; hooks neither construct it nor own its lifetime. The implementation may retain one named window property as the bridge, with its shape documented.

- [ ] Add coverage for absent music host, repeated initialization, and participant unregistering; preserve the existing rule that activating one medium pauses the other without automatic resumption.
- [ ] Move medium-neutral coordination to shared ownership and update consumers. Keep LiveSocket diagnostics in an explicitly named wiring function rather than growing application bootstrap logic.
- [ ] Standardize touched browser helpers on explicit ESM imports; prefer `.mjs` helpers rather than changing root package semantics blindly. Replace remaining source/data-URL loading where normal imports suffice. Add `npm test` for `node --test assets/test/*.mjs` and reuse it in the existing screenshots workflow's `video` job; preserve its browser and bundle checks rather than duplicating CI jobs.
- [ ] Update conventions with accepted ownership/API rules and check commands. Record implementation progress and actual verification in a dedicated GitHub issue or PR, linked to affected work such as #18 and #20. Distill lasting decisions and remove this temporary plan when finished.

**Acceptance:** medium coordination is independent of music initialization; application tests import the same helper modules as production; contributors have a named JavaScript check backed by the existing CI job.

## Verification and delivery

Planning baseline on 2026-11-05: `node --test assets/test/*.mjs` passed, 85 tests, zero failures. Node reported the existing ambiguous module-type warning. No running application, Docker checks, or target devices were exercised for this proposal. Git was clean before this document was added; the inspected branch was `main`.

For implementation, use the isolated development environment described in CONTRIBUTING: `sh scripts/dev/ensure.sh`. Run significant-work checks in that worktree's container: `sh scripts/dev/compose.sh exec -T app mix precommit`. Run `node --test assets/test/*.mjs` and the browser checks relevant to each task. Use the configured Tidewave server for runtime investigation only after confirming it points to this development instance. The commands and fixture setup for persistent music and fullscreen verification are in the testing convention.

Review priorities across tasks: stale asynchronous results, ended during replacement, errors and autoplay rejection, teardown/reconnect/navigation, and focus/fullscreen retention. Existing hardware verification gaps remain open; synthetic checks do not establish Safari/iPhone/TV compatibility. Coordinate Task 4 with the existing HLS optimization plan so behavior changes and structural refactoring remain independently reviewable.

Recommended first delivery: Tasks 1–2, followed by a review before splitting concurrency-sensitive music code. Evaluate success by whether a command or transition can be understood locally, without chasing hidden fallbacks or deeply nested branches. Do not enforce arbitrary line counts or extract tiny helpers solely to meet a metric.

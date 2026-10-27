# HLS playback reliability and efficiency implementation plan

> Execution: use `superpowers:executing-plans` to implement one bounded task at a time. Checkboxes track implementation, not approval or completion of this planning phase. No product changes or deployment are included in creating this document.

**Goal:** eliminate avoidable HLS work and playback failures while preserving authorized movie and episode playback on modest hardware.

**Architecture:** retain Video.js HTML controls, hls.js with native HLS fallback, progressive FFmpeg output, and the single-session manager. Fix confirmed lifecycle defects first; use measurements to decide whether additional optimizations justify their complexity.

**Stack:** Elixir, Phoenix/LiveView, FFmpeg, Video.js HTML 10.1.0, vendored hls.js 1.7.0, PromEx/Alloy/Grafana, ExUnit, Node tests and the existing Playwright harness.

**Basis:** the streaming audit in the preceding conversation, performed against `c80d5f19a50b0d0aba66949b719b5f936b8944d5`; [decision 0011](../decisions/0011-live-transcoding.md), [decision 0024](../decisions/0024-tab-playback-recovery.md), [decision 0025](../decisions/0025-consecutive-episode-parts.md), and the [project conventions](../conventions/).

## Scope and evidence

Confirmed findings: manifest polling continues while FFmpeg is paused; initial `serverPaused` ignores the server attribute; segments are read completely into BEAM memory; every HLS resource revalidates the original; the strategy set has no pure remux; every committed HLS seek replaces its session; routine HTTP requests are logged at info level by the endpoint.

Not established: excessive request frequency during actual NAS playback, harmful database load, a browser memory leak, orphaned FFmpeg processes, duplicate players, incompatible native-HLS startup, or a specific file benefiting from remux. These require verification tasks, not speculative fixes.

Audit checks passed: 40 Node tests, backend groups of 44 and 45 tests, and the production-hook browser harness in Chrome 155. A controlled frozen playlist with target duration two seconds produced approximately one manifest request per second while paused; destroying the hook stopped further requests. Simulated playlist disappearance exposed a terminal error for an initially paused hook. These are local synthetic results, not target-device verification. FFmpeg was unavailable locally during the audit.

## Global constraints

- Preserve movies, episodes, consecutive parts, multi-episode files, same-tab recovery, Spanish/English controls and fullscreen behavior.
- Reauthorize every media request; preserve current actor, association, revision and physical-source validation. Do not add an authorization cache.
- Keep the original media read-only, the five-minute idle policy, the single global HLS session and the existing storage bound unless separate evidence justifies changing them.
- Keep progressive sliding output. Do not add premature `ENDLIST`, label it VOD/EVENT, pre-generate whole movies, or change the four-second segment target merely to lower request counts.
- Retain the player, pinned dependencies and native fallback. No dependency upgrades, new streaming service, persistent segment cache or generic refactor.
- Metrics use fixed enums and route templates; never label them with session, file, viewer, tab, raw URL or media path. Correlation IDs remain in sanitized logs only.
- No deployment as part of implementation. Read `make help` and the deployment guide before any separately requested deployment.
- Keep this temporary plan with its change; remove it after completion and retain durable rules in decisions/conventions. Public documentation stays in English.

## Order and completion rules

Tasks 1–5 form the first delivery: baseline, pause correctness, resource cleanup verification, bounded segment delivery, and observability. Tasks 6–9 address measurement-gated optimizations and compatibility. Task 10 verifies the combined result on the target installation.

Each implementation task follows focused failing behavioral test → minimal fix → focused checks → review → `mix precommit` for significant work. A measurement-only task can finish with a documented decision to keep current behavior; it must record the measurements and rationale. Missing hardware evidence leaves that acceptance item pending rather than blocking independent local work or claiming compatibility.

Use one reviewable commit per task or coherent subtask. Inspect Git before each task and preserve unrelated changes. After significant implementation, update `docs/status.md` with actual verification and the next step; keep unexecuted work out of implemented behavior.

## Review focus

1. Initially paused recovery and autoplay rejection must bootstrap enough media to become usable without permanently polling a frozen manifest (Task 2).
2. Play/pause/seek and delayed messages crossing a source replacement must affect only the current session (Tasks 2–3).
3. Session cleanup or source invalidation during file transfer must not crash the manager or expose another source (Task 4).
4. A copied-video GOP longer than four seconds must not be mistaken for duplicate loads or fixed-duration segments (Tasks 1, 6, 9).
5. Native-HLS playback, touch/keyboard seeks, fullscreen and automatic part continuation must retain the global file timeline (Tasks 7, 9–10).

## Task 1 — Make the request baseline reproducible

**Files:** extend `scripts/verify_video_player.mjs`; add `scripts/measure_hls_playback.mjs` only if isolating measurement keeps the regression harness short; update `deploy/compose/monitoring.md` with the operator procedure. Disposable fixtures/results belong under `tmp/`; private HARs and media inventories must not be committed.

**Contract:** count requests at the HTTP boundary by manifest/segment, phase and status, with monotonic timestamps. Support evolving and frozen synthetic playlists, the existing completed fixture, and an explicit destruction phase. Output JSON containing phase duration, request counts, intervals, segment bytes and browser errors. Never present simulated output as real Phoenix/FFmpeg performance.

- [x] Add controlled scenarios: completed playlist, progressive playlist, frozen paused playlist, expired resource and destroyed hook. Verify the counter against a known server request sequence before using it to assess the hook.
- [x] Run each phase for at least two minutes when measuring cadence; count the bootstrap separately. Record actual `TARGETDURATION`, `EXTINF`, media sequence and `ENDLIST` instead of assuming four-second segments.
- [x] Document Grafana Query Inspector capture: effective `$window`, dashboard time range, legend reduction, query evaluation time, job/instance and release commit. The overview query is rolling `increase(...[$window])` by route/status, with `lastNotNull` in its legend; do not sum overlapping rolling points.
- [ ] Collect a target baseline when access is available: five minutes playing, two minutes paused, resume, one seek and navigation away; separately test a pause longer than five minutes. Include direct, audio-conversion and full-conversion sources with anonymous fixture labels.
- [ ] Record request/minute, unchanged-manifest fraction, HTTP mean/p95 and sample count, startup/seek time, FFmpeg/container CPU, container/BEAM memory, scratch usage and log lines/minute. Distinguish wall-clock observation time from playback position advanced.

**Acceptance:** the harness reproduces paused polling and no requests after teardown; the completed playlist stops recurring reloads; a sanitized measurement table clearly separates local synthetic and target results. Task 2 can proceed without NAS access.

Local verification is complete: clean commit `d5aee51`, Chrome 156.0.8078.49,
hls.js 1.7.0, 120-second phases, no browser exceptions and all report assertions passed.
The [monitoring guide](../../deploy/compose/monitoring.md#local-synthetic-baseline)
records the sanitized comparison. The target capture and its resource measurements
remain pending; do not mark those checkboxes complete from the synthetic run.

## Task 2 — Correct pause, load control and expired-session recovery

**Modify:** `assets/js/hooks/transcode_video.js`, `assets/js/hooks/video_player.js`, and only if necessary `assets/js/playback_recovery.mjs`, `lib/bolognesa_web/live_support/playback_events.ex` and `playback_state.ex`.

**Tests:** `assets/test/transcode_video_test.mjs`, `assets/test/playback_recovery_test.mjs`, the browser harness, and `test/bolognesa_web/live/movie/show/` / `episode/show/`.

**Interfaces:** preserve `playback_pause`, `playback_resume`, `playback_seek`, `playback_restore` and session identity checks. hls.js `stopLoad()`/`startLoad()` own network loading; native media pause/play owns decoding. Read initial `data-paused-server` rather than inventing an unpaused state. A failed or expired session must use the existing authorized replacement flow, never resurrect a destroyed controller.

- [ ] Add failing tests for initial server-paused state, manual pause, unchanged LiveView updates, duplicate pause/play events and a fatal error while initially paused.
- [ ] Add a real-hls.js browser regression for paused polling. Preserve initial bootstrap: stopping loading before manifest/metadata readiness must not deadlock `onReady`, autoplay or recovery. Allow only the minimum initial loading necessary, then quiesce a paused session.
- [ ] Coordinate stop/start loading with requested playback and server state. Coalesce repeated transitions. Handle play-before-pause-update and pause-before-resume-update without reviving an obsolete session.
- [ ] Test valid resume and expired resume independently: valid resume retains the session; expired resume creates exactly one replacement at the global position. Exercise delayed 404/fatal events from the previous source and rejected/missing recovery acknowledgements.
- [ ] Test autoplay rejection and paused reload recovery. A user waiting before first play must retain usable controls; idle expiry must not force the terminal error screen solely because playback remained paused.
- [ ] Keep native HLS behavior separate: no calls to hls.js methods when absent; no source clearing/reload merely to emulate pause without device evidence.

**Run:** `node --test assets/test/*.mjs`; `BOLOGNESA_TEST_BROWSER_CHANNEL=chrome npm run test-video-player -- tmp/videojs-fixtures`; focused movie/episode LiveView tests.

**Acceptance:** after bootstrap and in-flight requests settle, no recurring hls.js requests during a two-minute pause; playing continues progressive discovery; long-pause resume preserves position/pause intent; teardown generates no new loads. Compare request reduction with Task 1. Keep target-native pause traffic explicitly unverified until Task 9.

## Task 3 — Pin session ownership, concurrency and process cleanup

**Files:** `lib/bolognesa/playback/infrastructure/transcode_manager.ex`, `lib/bolognesa_web/live_support/playback_control.ex`, `playback_events.ex`; tests in `test/bolognesa/playback/transcode_manager_test.exs`, movie/episode LiveView tests and the browser harness.

**Contract:** one current session and one admitted FFmpeg producer. Same-actor replacement remains intentional; another actor receives `:busy`. Obsolete stop/touch/poll/error events cannot close a newer session. Manifest-only activity does not extend idle lifetime.

- [ ] Add missing concurrent-start/replacement coverage using monitored owners and barriers, not arbitrary sleeps. Verify different actors, two tabs for the same actor, stale owner-down notifications and invalid replacement preserving the previous session.
- [ ] Exercise idle cleanup, preparation timeout, normal completion, logout, source revision change and storage exhaustion using deterministic clock/state synchronization at the narrowest boundary needed. Keep test-only timing controls out of browser input.
- [ ] On Linux with real FFmpeg, observe OS PIDs and directory contents through pause, repeated seeks, tab closure, manager shutdown/restart and FFmpeg failure. Verify the old OS process actually exits, rather than inferring it from a closed Port.
- [ ] If termination/file-removal races reproduce, implement bounded process shutdown in the manager before final directory cleanup. Do not add a watchdog, process pool or SIGKILL escalation without a reproduced case and a test for its shutdown bound.
- [ ] Verify listener/source lifecycle: repeated `updated`, reconnect, source replacement and navigation keep one active media transport; destroyed transports make no further requests. Document same-actor tab replacement as a current limit instead of expanding session concurrency.

**Acceptance:** at most one admitted producer; actual OS cleanup demonstrated where tested; no stale action affects a replacement. Unreproduced orphan concerns close as investigated risks, with platform limits stated.

## Task 4 — Deliver segments without whole-file BEAM reads

**Files:** `lib/bolognesa_web/controllers/transcode_controller.ex`; controller tests for movies and episodes; `test/bolognesa_web/controllers/media_delivery_observability_test.exs` where shared delivery observations apply.

**Contract:** after existing authorization and source validation, segments use `Plug.Conn.send_file/3` or the bounded delivery mechanism supported by the configured adapter. Keep the small manifest read and `private, no-store`. Accept only the generated segment-name format. Do not reuse the original-source byte-range module blindly: it validates a different file identity.

- [ ] Add response tests for exact bytes, MIME, cache headers, authorization, invalid segment names, missing files and invalidated sources for both route families.
- [ ] Reproduce cleanup between validation and file opening, concurrent segment requests and a disconnected client against the real HTTP adapter. Define failure behavior before/after headers; never claim a new status after response headers were sent.
- [ ] Replace whole-segment `File.read` without adding a segment cache or a new producer. Preserve the session-touch rule for admitted segment delivery and explicit errors when the session vanished.
- [ ] Compare repeated large-segment transfers with Task 1: BEAM peak memory and response latency at one and several concurrent requests. Account for adapter/kernel buffering; `send_file` alone does not prove lower end-to-end memory.

**Acceptance:** correct bytes and unchanged access guarantees; no whole-segment binary assembled by controller code; no unexplained latency regression; adapter cleanup races produce controlled outcomes.

## Task 5 — Separate useful metrics from routine HTTP logs

**Files:** `lib/bolognesa/infrastructure/observability/playback_metrics.ex`, `playback_events.ex`, `observability.ex`, `lib/bolognesa_web/endpoint.ex`, `scripts/build-operational-dashboard.py`, generated `grafana/dashboards/operational.json`, `deploy/compose/monitoring.md`, `docs/conventions/observability.md`; tests in `test/bolognesa/infrastructure/prom_ex_test.exs`, `observability_test.exs`, `test/grafana/overview-test.py`.

**Interfaces:** reuse existing HTTP counters/histograms for request rate and endpoint latency. Add `TranscodeManager.runtime_snapshot/0 :: %{sessions: 0 | 1, ffmpeg_processes: 0 | 1, suspended_processes: 0 | 1}` for optional bounded polling metrics; expose counts only. A live session with an exited FFmpeg has zero producer count. These states do not prove the browser is playing.

- [ ] Add dashboard checks for manifest versus segment request/minute, HTTP mean/p50/p95 with sample counts, and selected-range versus rolling-window labels. Preserve movie/episode attribution and distinguish absent data from zero.
- [ ] Add snapshot/gauge tests across start, pause, resume, successful FFmpeg exit and cleanup. Polling must not scan directories or query SQL; monitoring-disabled startup remains supported.
- [ ] Measure preparation time from admitted session to ready/failure once per session, separately from session lifetime. Export bounded outcomes and retain the existing 30-second browser progress cadence. Do not label wall-clock producer lifetime as FFmpeg CPU time.
- [ ] Keep container CPU/memory as the initial FFmpeg-inclusive resource view. Add FFmpeg progress parsing only if Task 1 shows that conversion speed cannot otherwise explain stalls; allowlist numeric speed/frame progress and never export raw stderr.
- [ ] Configure endpoint-level dynamic logging for the known HLS routes to suppress routine info start/stop lines while retaining structured HLS failures, session lifecycle and HTTP telemetry. Verify both success and failures with captured logs; changing router log options alone is insufficient.
- [ ] Preserve all existing metric names. Add only bounded HLS error/retry enums if the controlled fault scenarios need them; coalesce repeated observations and test an explicit event budget. Do not emit a log per successful segment.
- [ ] Evaluate per-session request/byte summaries against measured diagnostic needs. If needed, accumulate bounded counters through existing manager messages and emit one sanitized closure summary; avoid extra synchronous manager calls per manifest solely for analytics. Otherwise record why route metrics plus correlated lifecycle logs suffice.

**Acceptance:** rate and latency are independently visible for both resources; active session/producer counts survive transitions correctly; routine HLS log volume falls while failure visibility remains; metric series and event counts remain bounded. Run the existing Grafana test script and relevant ExUnit tests; regenerate the dashboard from its generator.

## Task 6 — Prove and introduce narrowly scoped remux, if useful

**Files:** `lib/bolognesa/playback/domain/policies/transcode_strategy.ex`, `infrastructure/ffmpeg_args.ex`, `playback.ex`, strategy/session read-model types, `lib/bolognesa_web/components/player.ex`, observability strategy allowlists and translations; corresponding strategy/FFmpeg/manager/controller/browser tests. Search all `:audio_only | :full_transcode` contracts before introducing another value.

**Proposed interface, conditional on the experiment:** `:remux` as an additional delivery strategy; FFmpeg copies both streams into HLS. Direct-compatible MP4 stays direct. Initially consider only inspected MKV H.264/AAC sources; unknown or unsupported profiles keep current conservative behavior.

- [ ] Build anonymous synthetic and representative cases: H.264/AAC MKV, compatible MP4, H.264/AC3, unsupported video, no audio, stale/unknown inspection and long/irregular GOPs. Compare current fallback, remux and audio-only where applicable using actual FFmpeg/ffprobe.
- [ ] Gate implementation on correct audio/video, start/seek timing, segment publication, target-browser decoding and a repeatable CPU improvement over full conversion. A failed experiment ends with a recorded no-change decision, not forced remux support.
- [ ] If the gate passes, add failing strategy/argument tests: supported MKV selects `:remux`; MP4 remains direct; arguments copy audio/video and omit encoders; unsupported combinations retain existing behavior.
- [ ] Extend every strategy type, telemetry allowlist and translated mode label together. Preserve offset replacement, cleanup and retry limits. A remux failure may fall back once to the established compatible conversion; it must not cycle between direct/remux/transcode.
- [ ] Verify with real output streams and a complete short playback, including seek near EOF and consecutive episode parts. Update decision 0011 only after the behavior exists.

**Acceptance:** proven CPU benefit and passing target compatibility for the enabled profile, or an explicit evidence-based decision not to enable remux. No new default conversion based solely on a codec name.

## Task 7 — Avoid session replacement for safely buffered seeks

**Files:** `assets/js/hooks/transcode_video.js`, `assets/js/video_timeline.mjs`, their Node tests, browser harness; modify server events only if the existing pause/resume contract requires it.

**Interface:** keep `fileTimeline.seek(globalSeconds)`; calculate session-local time by subtracting the offset. A local seek is eligible only when the requested point lies strictly inside one actual native `video.buffered` interval, outside a 0.25-second margin at either edge, and there is no pending source replacement. All other seeks keep the existing server event.

- [ ] First run short seek benchmarks and fault scenarios; proceed only if avoiding a restart has measurable benefit and no timeline drift. Do not treat the synthetic full-file `seekable` range as buffered data.
- [ ] Add failing tests: nonzero offset, multiple buffered intervals, holes, exact edges, invalid positions, pending replacement, paused and playing seeks. Local path emits no `playback_seek`; remote path emits exactly one.
- [ ] Implement local seek without leaving `timeline.pending` or Video.js `seeking` stuck. Preserve pause intent and checkpoint updates; browser `seeked` and waiting/recovery diagnostics must still work.
- [ ] Verify keyboard, touch/drag commit, fullscreen, reload checkpoint and native-HLS behavior; seeks outside the window still replace the session and use the existing preparation cushion.

**Acceptance:** buffered seeks leave session ID and FFmpeg PID unchanged; out-of-buffer seeks remain correct; fewer restart events and shorter buffered-seek latency without skipped content. Otherwise retain current server seeks.

## Task 8 — Measure source-validation cost without weakening access

**Files for investigation:** `lib/bolognesa/playback.ex`, `infrastructure/local_media_file.ex`, `infrastructure/repositories/ecto_playback_repository.ex`, `lib/bolognesa/accounts/infrastructure/repositories/ecto_user_repository.ex`; existing source and authorization tests.

- [ ] Profile authentication SQL, source SQL, physical validation and resource delivery separately on representative media directories. Use local sampling/benchmarks, not high-volume permanent logs.
- [ ] Compare their duration and resource usage after Tasks 2 and 4; only optimize work that is material in the remaining endpoint latency or NAS load.
- [ ] If needed, reduce redundant projections/preloads or demonstrably repeated work within the same request. Preserve facade boundaries and inspect query plans before adding indexes.
- [ ] Any change must retain per-request session revocation, role/association checks, source revision, source deletion/replacement, symlink/ancestor and descriptor identity protection. Re-run existing adversarial source tests and add a regression for the measured redundancy.

**Acceptance:** measured improvement with unchanged guarantees, or a documented decision that current costs are acceptable. Cross-request authorization or physical-source caching is outside this plan; it requires a separate design if measurements justify it.

## Task 9 — Validate browser memory, native HLS and segment characteristics

**Files:** production-hook harness and measurement script; `assets/js/hooks/transcode_video.js` only for a proven adjustment; existing fixtures and `docs/status.md` for verified limits.

- [ ] Measure an extended hls.js playback (at least 30 minutes), buffered-range retention and browser memory. The current infinite back buffer is a risk, not proof of a leak; memory includes browser-owned buffers outside JS heap.
- [ ] If retention is harmful, compare `backBufferLength:60` with the baseline, keeping forward-buffer defaults initially. Verify full-file seeking, local seeks from Task 7 and long playback. Keep the change only with lower retained memory and no added stalls; do not conflate browser RAM with NAS RAM.
- [ ] On Safari/iOS and any actually used TV browser, establish which branch runs, where initial playback starts, and whether pause/resume, global offsets, reload recovery and EOF behave correctly. Do not switch native-versus-JS preference globally based on Chrome tests.
- [ ] With real FFmpeg, inspect several manifest snapshots, `TARGETDURATION` stability, `EXTINF`, sequence advancement, final `ENDLIST`, atomic publication and deletion timing for regular and irregular copied-video GOPs. Check the HLS requirements before changing flags or retention.
- [ ] Throttle network and conversion separately. Verify behavior when consumption falls behind the sliding window, conversion cannot sustain real time, storage fills or startup exceeds the preparation bound. Distinguish playback error, rebuffering and automatic live-edge movement.
- [ ] Make a narrowly scoped fix only for a reproduced failure, with a regression and renewed device checks. Keep four-second target and 12-entry window otherwise.

**Acceptance:** explicit results per actual browser/device and source class, with unknowns retained. Any memory/manifest adjustment has before/after evidence and preserves the preparation/storage budget.

## Task 10 — Combined acceptance and release readiness

**Files:** `docs/status.md`; decision 0011 and observability/testing conventions only where implemented behavior changed. Do not mark roadmap outcomes complete based solely on this plan.

- [ ] Run `node --test assets/test/*.mjs`, the production-player browser harness, the Grafana dashboard checks when changed, relevant real-FFmpeg integration checks and `mix precommit`.
- [ ] Exercise movies, episodes, consecutive parts, multi-episode files, direct delivery, audio conversion, full conversion and remux if enabled. Cover autoplay block, pause/long pause, buffered/unbuffered seeks, EOF, retry, reload, reconnect, navigation, logout and same-actor tab replacement.
- [ ] Repeat the Task 1 target scenario with the same media classes, browser, resource limits and scrape configuration. Compare bootstrap separately from steady playback; record intervals, requests, latency, CPU/memory, buffering, scratch use and log volume.
- [ ] Require zero recurring paused hls.js requests after settling, zero post-destruction requests, no duplicate producers, correct expired-session recovery and no new authorization failures. Hardware CPU/memory improvements require matched measurements, not assumed percentages.
- [ ] Review the full diff for security, source lifecycle, enum/type completeness, privacy and test evidence. Keep conditional tasks explicitly accepted, rejected with evidence, or pending device access.
- [ ] Update status with the implemented subset, commands/results, remaining blockers and next step. Prepare changes for review; do not publish or deploy under this planning request. Each task must be independently revertible through its commit, with regression checks rerun after reversal.

## Coverage and handoff

| Audit topic | Owner tasks |
| --- | --- |
| Metric window and actual request cadence | 1, 5, 10 |
| Progressive playlist versus VOD/ENDLIST | 1, 9 |
| Pause polling and initial pause defect | 2 |
| Duplicate mounts/listeners, reconnect and stale events | 2, 3 |
| Session expiry, tab changes, races and orphan risk | 2, 3 |
| Segment memory and concurrent delivery | 4 |
| Repeated SQL/physical validation | 8 |
| Logs, latency, retries, active resources and summaries | 5 |
| Avoidable full conversion and remux | 6 |
| Buffered seeks and FFmpeg restarts | 7 |
| Browser back buffer, native HLS, GOP and device limits | 9 |
| Series/parts preservation and target validation | 6, 7, 9, 10 |

Planning is complete when this document is reviewed for coverage and path correctness. Implementation, target measurements and deployment remain separate statuses.

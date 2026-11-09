# Playback flow simplification and efficiency implementation plan

> Execute with `superpowers:executing-plans`, one bounded task at a time. Checkboxes describe implementation work, not approval or release status. This planning change does not implement or deploy anything.

**Goal:** simplify playback coordination and remove redundant work while preserving server-owned delivery decisions and authorized media access.

**Architecture:** the server owns authorization, source safety, primary/fallback plans, attempt budgets and FFmpeg admission. The browser owns immediate media interaction, buffered seeks and checkpoint hints through one coordinator. Retain the mounted video element, existing player, progressive HLS and one shared producer; measure optimizations before claiming resource savings.

**Tech stack:** Elixir/Phoenix LiveView, PostgreSQL/Ecto, FFmpeg, current pinned Video.js HTML and hls.js, ExUnit, Node tests, existing Playwright harness and optional Telemetry/PromEx monitoring.

**Design basis:** the accepted server/browser responsibility split and [review in issue #10](https://github.com/avillen/bolognesa/issues/10#issuecomment-6726069448), against `7fcac2b`; decisions [0011](../decisions/0011-live-transcoding.md), [0024](../decisions/0024-tab-playback-recovery.md), [0025](../decisions/0025-consecutive-episode-parts.md), [0028](../decisions/0028-context-owned-browser-modules.md), and [conventions](../conventions/). This replaces the earlier HLS optimization task ordering; remux and selective conversion are already implemented and must not be rebuilt.

## Evidence and scope

Confirmed by code review: restored HLS playback first prepares offset zero and then replaces the session; compatible-action availability repeats source selection; every committed HLS seek requests replacement; segments are read into binaries; pause does not stop hls.js loading; browser coordination shares mutable pending/resume state; readiness requires four seconds of published output within a thirty-second preparation deadline. An initial numeric FFmpeg progress report and publication milestones now provide separate startup observations; they do not identify input-read or CPU delay by themselves.

The previous local synthetic measurement is retained as evidence: commit `d5aee51`, Chrome 156.0.8078.49, hls.js 1.7.0, 120-second phases. Frozen-playlist polling reproduced and teardown stopped requests. The [monitoring guide](../../deploy/compose/monitoring.md#local-synthetic-baseline) records the comparison. The latest review ran 140 Node tests successfully. Neither establishes target-server costs or universal browser support.

Unproven: harmful SQL load, browser memory leaks, orphaned FFmpeg processes, a performance benefit from splitting the manager, and the cause of any individual preparation timeout. Device and source details from private investigation must not appear in project artifacts.

## Global constraints

- Preserve movies, episodes, numbered parts, multi-episode files, natural continuation, same-tab recovery, English/Spanish controls and stable fullscreen elements.
- Server policy alone chooses original/remux/conversion and allowed fallback. Browser observations and positions are untrusted hints, never authorization or conversion rules.
- Reauthorize each media request; preserve current actor/session revocation, association, revision and physical-source identity checks. No cross-request authorization or filesystem-validation cache.
- Preserve one global producer, same-actor replacement, other-actor `busy`, five-minute idle expiry and the 512 MiB scratch bound. Manifest-only requests do not refresh idle lifetime.
- Keep originals read-only. Keep four-second HLS target, 12-entry sliding playlist and progressive publication unless a separate measured change is reviewed. No premature ENDLIST, VOD/EVENT relabeling or whole-file pre-generation.
- Keep the present safe format envelope and one automatic eligible decode recovery per attempt. Seek/reconnect do not renew its budget. Do not broaden automatic recovery to network or ambiguous native errors.
- Keep pinned dependencies and transport preference. No new streaming service, persistent media cache or dependency upgrades.
- Keep one owner for each state: socket for server presentation/attempt state, browser coordinator for immediate lifecycle, media element for position/duration/actual pause. No mirrored copy of all socket assigns.
- Diagnostics use bounded stages/reasons and existing sanitized emitters. No raw reports, media-tool stderr, titles, paths, URLs, user-agent or private device details. IDs stay out of metric labels.
- No deployment. Significant implementation requires `sh scripts/dev/local.sh test` (runs `mix precommit`) plus relevant browser/Node/FFmpeg checks. Planning-only changes need document checks.

## Delivery order and review gates

| Delivery | Tasks | Result |
| --- | --- | --- |
| A | 1–3 | Reproducible evidence, actionable failures and correct pause lifecycle |
| B | 4–5 | One negotiation decision and one initial preparation at the desired position |
| C | 6–7 | Explicit browser coordination and measured startup policy |
| D | 8–10 | Buffered seeks, file-backed segments and useful bounded observations |
| E | 11–12 | Measured query/probe improvements and a decision on manager isolation |
| Acceptance | 13 | Combined regression and remaining hardware evidence |

A task depends on preceding tasks unless stated otherwise. Task 9 can proceed after 1; task 10 after 3 and 7. Task 12 starts as a decision/measurement task and may conclude without a process split. Do not bundle all deliveries into one PR.

For functional changes: add the lowest useful failing behavioral regression, confirm its failure, implement, then run focused and required checks. For structural refactors use existing regressions and add missing transition coverage before moving ownership. Review each delivery, commit coherent changes and record actual results/remaining work in #10 or its PR. No checkbox is complete merely because its proposal is written here.

## Review focus

1. Initially paused playback and rejected autoplay must bootstrap without deadlock and remain playable (3, 5, 6).
2. Old probe completions, restore acknowledgements, pause updates, errors and EOF crossing an episode/retry must not affect the new attempt (2, 3, 5, 6, 13).
3. Long/irregular copied GOPs and slow input must distinguish progress from readiness; no assumed four-second segment duration (1, 7, 13).
4. Source invalidation, cleanup and disconnected clients during delivery must retain access guarantees and controlled failures (9, 11, 12).
5. Native HLS must retain global offsets, pause, continuation and stable player identity without assuming hls.js controls apply (3, 5–8, 13).

## File responsibilities and interfaces

- `lib/bolognesa/playback/domain/policies/negotiation.ex`: pure candidate, primary/fallback and rejection policy; no browser, DB or filesystem effects.
- New `domain/value_objects/playback_decision.ex`: `%PlaybackDecision{primary: DeliveryPlan.t(), fallback: DeliveryPlan.t() | nil}`; both plans derive from the same validated source/report. Primary plan's reason remains the selected-delivery reason.
- `application/use_cases/select_video_plan.ex` and `lib/bolognesa/playback.ex`: evolve to `select_video_decision(actor, ref, file_id, issued, raw, generation)` returning `{:ok, PlaybackDecision.t()} | {:error, reason}`. Migrate callers/tests together and remove the old selector after migration; no permanent parallel API.
- `lib/bolognesa_web/live_support/playback_control.ex`, `playback_events.ex`, `playback_state.ex`: UI coordination, current attempt/fallback and authorized effects. Display errors as bounded reason/stage plus eligible actions; business rules remain in Playback.
- New `assets/js/video/player/playback_session.mjs`: browser coordinator composed by `video/hooks/video_player.js`; keep `source_controller.mjs`, controllers, recovery and diagnostics as collaborators rather than copying Music's whole layer tree.
- New `assets/js/video/player/initial_playback.mjs` and `lib/bolognesa_web/live_support/playback_start_hint.ex`: storage hint extraction and closed envelope validation, respectively. No new persisted progress record.
- New `lib/bolognesa/playback/infrastructure/hls_readiness.ex`: filesystem/playlist inspection with `check(directory) :: :waiting | :ready | {:error, reason}`. Readiness I/O leaves the public facade; the facade delegates and LiveView retains generation-bound notification/polling until task 12's decision.
- `transcode_controller.ex`: authorized HTTP delivery. `transcode_manager.ex`: atomic single-slot ownership and current process lifetime until task 12; no worker split as incidental cleanup.

## Task 1 — Refresh reproducible baselines

**Files:** `scripts/playback/measure-hls-playback.mjs`, `hls-measurement-helpers.mjs`, `verify-video-player.mjs`, `verify-negotiated-liveview.mjs`; `assets/test/hls_measurement_test.mjs`; `deploy/compose/monitoring.md` only if invocation changes.

**Produces:** JSON measurements by bootstrap/playing/paused/resume/seek/destroyed phase; anonymous fixture labels, counts, statuses, bytes, elapsed time and errors. Add producer-start count, startup-to-ready time and source-read count at controlled test boundaries, not production raw SQL logs.

- [ ] Verify existing request accounting against known synthetic sequences; add regression assertions for any added counters.
- [ ] Capture completed/progressive/frozen/expired sources with two-minute request phases, plus restored nonzero startup and buffered/unbuffered seeks. Preserve initial baseline results before changing behavior.
- [ ] Generate disposable regular/irregular-GOP fixtures under `tmp/` using the existing FFmpeg verifier. Record actual EXTINF/TARGETDURATION, not an assumed segment duration.
- [ ] When target access is available, measure five minutes playing, two paused, resume/seek/navigation, then a separate pause exceeding five minutes; separate SQL, physical validation, producer/container CPU, BEAM memory and scratch usage.
- [ ] Record which measurements are synthetic, actual local FFmpeg, browser or target observations. Missing target evidence does not block independent correctness work.

**Check:** `node --test assets/test/hls_measurement_test.mjs`; `npm run measure-hls -- tmp/videojs-fixtures`. Acceptance: trustworthy phase accounting and repeatable before/after input, with no unsupported resource claims.

## Task 2 — Actionable rejection and failure states

**Files:** `negotiation.ex`, `playback_state.ex`, `playback_events.ex`, `lib/bolognesa_web/components/player.ex`, English/Spanish Gettext catalogs; `test/bolognesa/playback/negotiation_test.exs`, `test/bolognesa_web/live_support/playback_events_test.exs`, movie/episode LiveView tests.

**Produces:** closed UI failure stages `inspection`, `compatibility`, `preparation`, `playback`; keep backend reason atoms. Derive eligible refresh/original/retry/compatible actions from validated failure context. Store these presentation fields on the socket, not in a second state store.

- [ ] Add regressions: valid copy candidate plus absent encoding color facts must not be mislabeled missing inspection when the report is unknown/unsupported; genuinely missing required facts still permit refresh. Preserve explicit HDR exclusion.
- [ ] Distinguish rejection under auto versus compatible preference; no safe encoder is different from no client support. Missing encoding facts may explain why a fallback cannot be created without declaring the original inspection obsolete.
- [ ] Render refresh only for inspection-related failure. Busy, preparation timeout, network interruption and uncertain browser support offer relevant actions and distinct localized feedback; never expose raw backend errors.
- [ ] Verify late capability timeouts cannot replace a newer error/attempt, and validate movie/episode action parity.
- [ ] Run focused negotiation/LiveView tests and native precommit; review translations and selectors before committing.

**Acceptance:** every displayed action can address its failure class; metadata, compatibility and preparation remain distinguishable in UI and sanitized diagnostics.

## Task 3 — Pause intent and HLS loading lifecycle

**Files:** `assets/js/video/player/controllers/hls.mjs`, `playback_recovery.mjs`, `video/hooks/video_player.js`; `playback_events.ex` if acknowledgement handling needs adjustment; `assets/test/transcode_video_test.mjs`, recovery tests and production-hook harness.

**Contract:** retain `playback_pause/resume/seek` identity checks; initialize from `pausedServer`. Distinguish desired pause, server acknowledgement and transport loading; repeated acknowledgements have no extra effects.

- [ ] Add failing cases for initially paused source, play before pause acknowledgement, pause before resume acknowledgement, duplicate events, autoplay rejection and old-session errors.
- [ ] Allow manifest/metadata bootstrap before quiescing a paused hls.js transport; call stopLoad/startLoad only on actual transitions. Preserve useful error handling during pending resume.
- [ ] Keep valid resume on the same session and expired resume on one authorized replacement at the global position. Missing/rejected responses cannot strand controls.
- [ ] Add actual-hls.js frozen-playlist pause coverage: after in-flight requests settle, no recurring requests over two minutes; progressive loading resumes on play; no requests follow destroy.
- [ ] Verify native HLS separately without clearing/reloading its source just to emulate stopLoad. Run Node, relevant LiveView, browser and native precommit checks.

**Acceptance:** paused startup stays usable; long-pause resume retains position/intent. Native request cadence remains an evidence item rather than a promised hls.js result.

## Task 4 — One primary/fallback negotiation decision

**Files:** new `playback_decision.ex`; `negotiation.ex`, `select_video_plan.ex`, `playback.ex`, `playback_control.ex`, `playback_state.ex`; negotiation and playback event tests.

**Consumes/produces:** validated CapabilityReport and current source -> `PlaybackDecision` as defined above. Auto keeps current least-cost candidate ordering. Fallback keeps current full H.264/AAC-or-silent eligibility, must be positively supported and different from primary; otherwise nil.

- [ ] Add domain tests for primary/fallback combinations, unknown/negative observations, stale revision and selected plan already equal to compatible output.
- [ ] Return both choices from one authorized source read and one report validation. Remove the availability-only call to select_video_plan and migrate facade callers atomically.
- [ ] Retain only the server-selected fallback needed by recovery; browser cannot supply a plan. Revalidate source/plan when preparing either choice; preserve current one-shot budget across seek/reconnect.
- [ ] Add a repository-read-count regression specifically for the removed redundant selection. Keep preparation's fresh authorization/read; do not optimize away distinct trust boundaries.
- [ ] Verify retry/new-attempt versus reconnect budgets and stale error events; run negotiation, LiveView, FFmpeg and native precommit checks.

**Acceptance:** one decision drives playback and compatible-action visibility, without policy duplication or broader recovery behavior.

## Task 5 — One initial preparation at the checkpoint

**Files:** new `initial_playback.mjs`, `playback_start_hint.ex`; hook, recovery, control/events; `assets/test/playback_recovery_test.mjs`, `playback_capabilities_test.mjs`; new `assets/test/initial_playback_test.mjs`, new `test/bolognesa_web/live_support/playback_start_hint_test.exs`; playback event tests and negotiated LiveView verifier.

**Contract:** capability event remains the bounded version-one report, optionally augmented with `initial: {position_ms: integer, paused: boolean}`. The web adapter strips/validates that optional field before passing the unchanged closed report to CapabilityReport.new/3. Validate the entire envelope at <=8,192 external bytes; absent/invalid hint becomes offset 0/current default intent, never bypasses report validation. Position is 0..2,147,483,647 and below known duration. The accepted generation/file binding comes from server state, not a client ID.

- [ ] Read a matching checkpoint before sending the capability event; retain current 12-hour lifetime and viewer/content/file matching. Storage failure must not delay reporting.
- [ ] Test old clients with no hint, corrupt/expired/mismatched checkpoints, negative/noninteger/oversized positions, unknown keys and oversized envelopes. Reject unknown envelope keys; ignore invalid hint values without accepting an invalid report.
- [ ] Prepare the selected plan once at the accepted HLS offset and retain requested pause intent. For direct playback, restore after metadata as today. Ignore hints received after the checking generation ends.
- [ ] Stop issuing playback_restore for initial HLS restore once both sides migrate; remove that obsolete event/acknowledgement timer and its replacement-only tests, retaining restore success/failure diagnostics. Ordinary seeks must never reinstate the checkpoint.
- [ ] Verify a nonzero reload produces one FFmpeg start, first attachment at the restored timeline, and usable controls after autoplay rejection; run Node, LiveView, real negotiated browser and native precommit checks. Update decision 0024 only to implemented behavior.

**Acceptance:** no throwaway offset-zero HLS producer; untrusted hints cannot select another file or renew recovery budgets.

## Task 6 — Consolidate browser playback transitions

**Files:** new `playback_session.mjs`, new `assets/test/video_playback_session_test.mjs`; hook, source controller, HLS/direct controllers, recovery, diagnostics and existing source/transport tests; frontend convention/decision 0028 when implemented.

**Interface:** `createPlaybackSession({video, checkpoint, diagnostics, createSource, probeCapabilities, readInitialHint, pushEvent}) -> {update(config), retry(), disconnected(), reconnected(), destroy()}`. The hook composes concrete adapters and delegates lifecycle. The coordinator issues capability probes, reads the initial hint and discards obsolete completions; the hook no longer owns a second probe generation. Coordinator phases: checking, preparing, attaching, ready, error, destroyed. Server config remains authoritative; video remains authoritative for actual currentTime/paused/duration.

- [ ] Pin public event traces before refactoring: source replacement, pending seek, retry, old probe/ready callback, rapid episode change, EOF and destroy. No tests for arbitrary private field layout.
- [ ] Move orchestration into the coordinator incrementally. Give each attachment a generation guard; let transports report ready/error and dispose resources. Checkpoint storage no longer drives source creation through a hook retry callback.
- [ ] Keep timeline offset/seek interface and transport-local resources, but centralize pending replacement and intent transitions. Avoid duplicating the media element's actual pause/time in mutable stores.
- [ ] Make update/destroy idempotent; one controller and listener set survive unchanged updates/reconnect. Stale completion after destroy must have no effects.
- [ ] Run Node, production-hook and real episode/part fullscreen checks, then native precommit. Preserve the existing mounted frame and diagnostics limits.

**Acceptance:** one explicit browser lifecycle owner, smaller hook, unchanged authorized event semantics and no new global player store.

## Task 7 — Readiness and bounded startup policy

**Files:** new `hls_readiness.ex`, new `test/bolognesa/playback/hls_readiness_test.exs`; playback facade, state/events, FFmpeg args only if measurements justify them; transcode manager tests and measurement harness.

**Interface:** `HlsReadiness.check(directory)` returns waiting/ready/error after parsing actual published durations and regular referenced segments. Extract existing >=12 seconds or ENDLIST behavior first. Keep the current 12,000 ms deadline until the measurement decision below; no hidden timeout increase.

- [ ] Add fixtures for partial/atomic manifests, missing segments, short ENDLIST, regular/long/irregular GOPs and stopped producer. Test using deterministic files and messages.
- [ ] Move readiness I/O out of the facade, keeping generation-bound checks and one terminal outcome. Record admitted-to-ready/failed duration separately from total session lifetime.
- [ ] Compare startup across remux, audio/video/full conversion and slow input. Record burst input seconds, published seconds, first segment and time-to-playable separately.
- [ ] Decide and record whether to retain or change the startup cushion/deadline using task 1's results. Any change gets its exact threshold, finite bound, failed regression and renewed browser/underrun check in this task's PR before implementation. Do not implement an adaptive retry policy without those facts.
- [ ] Verify failures without progress remain bounded, slow progress cannot occupy the slot indefinitely, ENDLIST is never fabricated, and short files still start. Run relevant ExUnit/FFmpeg/browser and precommit checks.

**Acceptance:** readiness has a coherent owner, explicit progress evidence and a justified startup policy. A measured decision to retain thresholds is a valid result.

## Task 8 — Local buffered seeks

**Files:** HLS controller, `timeline.mjs`, new `assets/js/video/player/buffered_seek.mjs`, new `assets/test/buffered_seek_test.mjs`, transport tests and browser harness.

**Interface:** `bufferedSeekTarget(video, globalSeconds, offsetSeconds) -> number | null`; return local seconds only strictly inside one real `video.buffered` interval, with 0.25 seconds excluded at each edge. Pending replacement always uses existing suppression.

- [ ] Measure task 1's local/unbuffered seek paths before changing them. Add tests for nonzero offset, holes, interval edges, invalid numbers and paused/playing intent.
- [ ] Resolve eligible seeks through currentTime without playback_seek; otherwise send exactly one existing server event. Never treat synthetic full-file seekable as downloaded bytes.
- [ ] Clear Video.js seeking/pending correctly; preserve checkpoint, diagnostic and fullscreen behavior. Verify drag commit, keyboard and touch interaction with native and JS transports where available.
- [ ] Compare seek-to-progress time and restart count; run Node, browser, relevant LiveView and precommit checks.

**Acceptance:** buffered seek retains session and OS PID with no drift; out-of-buffer seek retains correct server replacement. Keep current behavior if benefit/correctness cannot be demonstrated.

## Task 9 — File-backed segment delivery

**Files:** `lib/bolognesa_web/controllers/transcode_controller.ex`; movie/episode transcode controller tests and media-delivery observability tests.

**Contract:** keep small manifest reads and `private, no-store`; segments use the adapter-supported file-backed path after current authorization, name/regular-file validation and admitted session touch. No cross-request media cache.

- [ ] Add response regressions for exact bytes, MIME, invalid name, missing/invalidated source, missing session and changed revision for both route families.
- [ ] Exercise cleanup between validation/open, concurrent transfer and disconnected client using the real HTTP adapter. Pin controlled outcomes before/after headers; do not promise a replacement HTTP status after sending headers.
- [ ] Replace segment File.read, preserving failure telemetry and existing source protection. Do not reuse original-file range machinery that validates a different identity.
- [ ] Measure peak BEAM memory and latency with one/several transfers against the same fixtures; account for adapter/kernel buffers. Run controller/integration tests and native precommit.

**Acceptance:** no whole-segment binary assembled by the controller; access guarantees/bytes remain correct and resource claims have measured support.

## Task 10 — Bounded startup and resource observations

**Files:** `lib/bolognesa/infrastructure/observability/playback_events.ex`, `playback_metrics.ex`, `observability.ex`, `lib/bolognesa_web/endpoint.ex`, manager, `grafana/build-overview.py`, generated dashboard, monitoring guide; `test/bolognesa/infrastructure/observability_test.exs`, `prom_ex_test.exs`, `test/grafana/overview-test.py`.

**Interface:** `TranscodeManager.runtime_snapshot/0 -> %{sessions: 0 | 1, ffmpeg_processes: 0 | 1, suspended_processes: 0 | 1}` from in-memory state, no SQL/directory scan. Count readiness once per session with bounded outcome/reason/stage.

- [ ] Verify snapshot values through start/pause/resume/process exit/cleanup; a retained finished session has zero producer count. Monitoring-disabled startup must work.
- [ ] Reuse existing HTTP measurements; distinguish manifest/segment request rate, latency sample counts and preparation latency from session lifetime or CPU time.
- [ ] Suppress routine successful HLS request info logs at the endpoint boundary while preserving structured failures and HTTP telemetry. Capture both success/failure logs in tests; do not log reports or chunk contents.
- [ ] Preserve existing metric names, bounded labels and event budgets. Add session summaries or numeric FFmpeg progress only if task 1/7 evidence shows a concrete missing diagnostic; never export raw stderr.
- [ ] Run Grafana tests/regenerate its JSON if changed, relevant ExUnit and native precommit; compare log volume and failure visibility.

**Acceptance:** preparation failures are distinguishable without high-volume logs or sensitive data, and counts represent actual resources rather than assumed playback.

## Task 11 — Measured query and capability-probe simplifications

**Files:** playback facade/repository, `local_media_file.ex`, capability probe module and tests; relevant source/authorization tests; measurement harness.

- [ ] Profile SQL/source projection/physical validation/delivery separately after preceding improvements. Compare a narrower authorized session-delivery projection against current full inspection/tracks loading.
- [ ] If material, add the narrow repository method with a typed source identity result, preserving association/revision/physical checks; define its exact fields in the task PR from existing Source consumers before coding. Add invalidation/revocation/adversarial source regressions and query-count evidence. No indexes without query-plan evidence.
- [ ] Deduplicate identical complete browser probe configurations within one attempt, including transport/type and every codec/dimension/rate field. Add tests that identical probes share work but different configurations do not; retain explicit negative veto and aggregate unknown-on-deadline behavior.
- [ ] Do not add cross-document persistent capability caches. A document-local cache is deferred until repeated-probe latency is material and its invalidation contract is separately specified; no user-agent capability table.
- [ ] Run relevant Node/source/LiveView/precommit checks; record before/after or a measured decision to retain existing reads/probes.

**Acceptance:** fewer demonstrably redundant reads/probes with unchanged safety and deadline semantics; no speculative cache infrastructure.

## Task 12 — Decide whether session effects need isolation

**Files for measurement:** manager, supervisor in `lib/bolognesa/application.ex`, manager tests and real FFmpeg lifecycle checks. **Conditional files:** new `infrastructure/transcode_session_worker.ex` and worker tests only after the decision.

**Decision inputs:** manager call latency during filesystem preparation, signals, scratch scans and cleanup; OS process lifetime on replacement/shutdown; complexity of current ownership/readiness handling. Retaining the single manager is an acceptable result.

- [ ] Add deterministic concurrent start/replacement and stale-owner tests. Cover same actor/two tabs, different actors/busy, failed preflight preserving current session, stale DOWN/stop/touch and logout.
- [ ] Observe actual OS PIDs through suspended stop, repeated seeks, producer failure, owner exit and manager shutdown. Closing a Port alone does not establish process death.
- [ ] Record isolate/retain decision. If isolation is justified, first specify manager/worker start-stop-status message contracts and bounded OS shutdown in this plan's PR; review that concrete contract before implementation. No process pool or concurrency increase.
- [ ] For an approved split, manager reserves/replaces one slot atomically; worker owns Port, directory/readiness/signals/cleanup and monitors the actual LiveView owner, not a short-lived task. No new producer launches until old producer exit is confirmed; failed preflight preserves it and failed launch releases the reservation.
- [ ] Verify bounded termination before directory removal, stale generations, supervisor restart, limits and in-memory snapshots; no orphan claim without Linux process evidence. Run manager/worker/native precommit plus real FFmpeg acceptance.

**Acceptance:** either documented retain rationale, or proven single-producer/ownership guarantees with responsive arbitration and independently testable resource lifetime. Measurements/review gate this optional larger refactor.

## Task 13 — Combined acceptance and handoff

**Files:** existing negotiated-output/LiveView/production-hook harnesses; decisions 0011/0024/0028, testing/frontend conventions and playback guide only for behavior actually delivered. Keep changelog as one concise Unreleased playback point.

- [ ] Run `node --test assets/test/*.mjs` and `sh scripts/dev/local.sh test`; run source-derived FFmpeg output checks and production-hook/negotiated LiveView browser harnesses per the testing convention. Run Grafana checks when affected.
- [ ] Cover original/remux/audio/video/full conversion, silent media, absent optional color facts, explicit HDR rejection, missing analysis and unknown capability results.
- [ ] Cover initial nonzero paused/playing checkpoint, rejected autoplay, long pause/expiry, local/remote seeks, genuine decode/network/ambiguous errors, retry, reconnect, navigation, logout and same-actor tab replacement.
- [ ] Verify real EOF across parts/episodes, global timeline and stable fullscreen frame; late callbacks/events from outgoing content cannot affect new content.
- [ ] Repeat matched measurements: startup and seek latency, producer starts, source reads, paused/post-destroy requests, memory/CPU/scratch/log volume. No recurring paused hls.js requests after settling, no post-destroy requests, no duplicate producer; report actual distributions/sample counts rather than invented percentage targets.
- [ ] Run at least 30 minutes of playback for retained buffer and memory behavior. If harmful retention is demonstrated, evaluate bounded backBufferLength separately with the same fixtures; do not label growing memory a leak without evidence.
- [ ] Record native-HLS and actual target results separately. Missing hardware evidence remains pending and does not become a compatibility claim. Keep private device/installation/source facts out of all artifacts.
- [ ] Review the full delivery diff, incoming history/privacy scan before pushing, CI and remaining gaps; update #10/PR with actual checks and next steps. Do not close the issue/milestone solely because this plan exists or local suites pass. No deployment.

## Plan completion and later maintenance

Self-review must check file paths, interface consistency, review-focus coverage and preservation of prior measurement/cleanup/observability work. Measurement gates are explicit decisions, not permission to implement an unspecified algorithm. Implementations must update the plan with concrete threshold/worker/projection contracts when their evidence gates are reached.

After delivered tasks finish, remove this temporary document or distill lasting rules into the existing decisions/conventions. GitHub remains the record of scope, measured evidence and outstanding acceptance.

# Capability-based playback implementation plan

> Execute with `superpowers:executing-plans`, one task at a time, using native development. This temporary plan follows the approved [design](playback-negotiation.md).

**Goal:** choose direct, remux, audio conversion or video conversion from validated client reports and authorized source facts.

**Architecture:** Libraries owns inspection facts. Playback owns candidates, report validation and delivery plans. LiveView owns negotiation generations and attempt budgets; video modules probe server configurations and consume the selected transport.

**Stack:** Elixir/Phoenix, PostgreSQL, FFmpeg, Video.js, hls.js, ExUnit, Node and existing Playwright harnesses.

## Global constraints

Preserve per-request authorization/revision/source checks, read-only originals, one FFmpeg session, five-minute idle expiry, 512 MiB storage bound, 12-second preparation and four-second segment target. Reports allow six results, 8 KiB, 64-byte tokens and a three-second detection deadline. Generated video targets SDR H.264 Constrained Baseline level 4.1, 8-bit 4:2:0, at most 1920x1080/30 fps, CRF 25, ultrafast, two threads, 8 Mbps VBV maximum/16 Mbit buffer. Task 0 must verify its actual SPS/codec identifier before candidate contracts are implemented; `-profile:v high` with ultrafast does not establish a High-profile bitstream. Generated AAC-LC is 128 kbps, 48 kHz, at most stereo. No HDR tone mapping, HEVC HLS, dependency upgrade or deployment.

Run `sh scripts/dev/local.sh setup` once per implementation worktree. Run focused Mix commands with that worktree's environment from `scripts/dev/local.sh`; run `sh scripts/dev/local.sh test` after each significant implementation task, not only at final acceptance. Keep old public playback callers working until task 5 switches them: task 4 introduces plan-based execution alongside the old entry points, with an explicit temporary adapter removed in task 5 and existing LiveView tests passing at both commits.

## Review focus

- Legacy inspections and missing color facts must not enable unsafe conversion (tasks 1–3).
- Default versus explicitly mapped tracks must agree with the probed configuration (tasks 1–4).
- Late browser reports and errors must not replace a newer selection (task 5).
- Seek/reconnect/checkpoint restoration must retain the current attempt's fallback budget (task 6).
- Native HLS and silent media must work without assuming desktop Chrome proves iPhone support (tasks 0, 4, 7).

## Task 0 — Verify the output envelope before locking probes

**Files:** extend `scripts/playback/verify-video-player.mjs` only where needed for repeatable hook checks. Keep generated fixtures, codec records and measurement reports under `tmp/`; record sanitized outcomes in #10.

**Dependency:** tasks 1–2 may proceed independently. Tasks 3–6 require this gate's local FFmpeg/browser results before fixing encoded candidate identifiers and transport eligibility. Physical iPhone acceptance remains separate and pending if no device is available.

- [x] Generate short, explicitly SDR H.264/AAC and silent fixtures using the proposed ultrafast encoder settings with `-profile:v baseline -level:v 4.1`. Include ordinary and long-GOP inputs and a nonzero seek offset.
- [x] Inspect SPS/configuration bytes, profile, level, pixel format, actual dimensions/frame rate and AAC configuration with ffprobe. Pin the RFC 6381 identifier from the real output; do not derive it from the requested profile name. Repeat at the 1920x1080/30 fps bound and assert the same advertised codec constraints.
- [x] Remux a synthetic H.264/AAC MKV with absolute stream maps and copy/copy into the existing sliding MPEG-TS layout. Verify the encoded and remuxed fixtures through the production hook in an available actual desktop browser, including startup, seek and EOF; compare matched remux/full-encode CPU observations.
- [ ] Exercise native HLS on an available native-HLS browser with the same fixtures. If unavailable, document this limitation and keep native transport eligibility explicitly inferred; desktop HLS.js success must not be presented as native/iPhone proof.
- [x] Record the verified codec identifier, commands, browser versions, remux outcome and measurement method. Stop dependent contract work if local output or HLS.js consumption fails; revise the output envelope before proceeding. Do not enable a broader remux profile based solely on codec names or assumed savings.

Local output/browser gate passed with `avc1.42C029` at both 320x180/24 fps and 1920x1080/30 fps. Native HLS and physical iPhone verification remain unrun; native eligibility remains inferred. Actual commands/results and synthetic CPU observations are recorded in #10.

## Task 1 — Persist bounded negotiation facts

**Modify:** Libraries `domain/value_objects/inspection/technical_track.ex`, `infrastructure/services/ffprobe_media_probe.ex`, `ffprobe_json.ex`, `infrastructure/repositories/ecto_inspection_repository/inspection_mapper.ex`; Playback `domain/read_models/technical_track.ex` and `infrastructure/repositories/ecto_playback_repository.ex`.

**Contract:** additive optional fields for original stream index, default/attached-picture dispositions, profile/level, pixel format/bit depth, dimensions, rational frame rate, bitrate, sample rate/channels and color facts. Legacy JSON loads with unknown values. Retain normalized fields only; raw probe output never becomes diagnostics.

- [x] Add failing parser/mapper/projection tests for legacy JSON, malformed optional facts, attached pictures, original indexes and unknown color metadata.
- [x] Run `mix test test/bolognesa/libraries/ffprobe_json_test.exs test/bolognesa/libraries/ffprobe_media_probe_test.exs` in the native worktree environment; confirm the new assertions fail.
- [x] Extend validation, ffprobe entries and both context-owned projections; preserve the 256 KiB/128-stream limits.
- [x] Run the focused tests and repository round-trip tests; require zero failures. Review and commit `feat(playback): retain bounded negotiation facts`.

## Task 2 — Exact codec identifiers and metadata refresh

**Create:** Libraries inspection codec-configuration parser beside `ffprobe_json.ex`; `lib/bolognesa/libraries/application/use_cases/request_inspection_refresh.ex`; `lib/bolognesa/libraries/infrastructure/repositories/ecto_inspection_repository/inspection_request.ex`; `test/bolognesa/libraries/request_inspection_refresh_test.exs`. **Modify:** Libraries facade, `application/ports/repositories/inspection_repository.ex`, `infrastructure/repositories/ecto_inspection_repository.ex`, `ecto_scan_repository.ex` and the modules from task 1.

**Contract:** codec parser returns a validated RFC 6381 identifier or unknown. Playback plan carries selected absolute stream indexes, delivery, independent stream actions, output envelope, transport and bounded reason. Select first non-picture video and first audio by index, with optional audio. An authorized explicit metadata refresh schedules existing durable inspection once per action without changing file identity.

**Refresh API:** `Libraries.request_inspection_refresh(actor, file_id, expected_revision)` delegates to `RequestInspectionRefresh.call(actor, file_id, expected_revision, repository)`. Return `{:ok, :enqueued | :already_pending}` or `{:error, :forbidden | :not_found | :missing | :source_changed | :refresh_limited | :unavailable}`. The use case authorizes the administrator before calling the port's `request_refresh(file_id, expected_revision, now)` operation. Inside one transaction, lock the media file before its inspection, require an available movie/series file at the expected revision, and coalesce an existing pending/running request for that revision without replacing its token/job. Music requests return `:not_found`.

Extract the scan repository's private inspection scheduling into the shared `InspectionRequest` collaborator; retain inventory/inspection/job transaction atomicity in scans. For an eligible explicit refresh, create a fresh token, reset inspection state and insert/link its Oban job in the same transaction. Roll back both on enqueue failure. Use a 30-second per-file cooldown based on the persisted inspection `updated_at` for terminal requests; completion/failure restarts that conservative cooldown. A successful enqueue always invalidates the previous token. This needs no migration and must not schedule identification or change file revision/identity. Duplicate browser events during an active request return `:already_pending`; repeated completed requests inside the cooldown return `:refresh_limited`.

- [x] Add failing AVC/HEVC configuration-record tests, truncated/oversize data tests tests. Add refresh tests for unauthorized/missing/music files, stale revisions, cooldown, atomic enqueue rollback and concurrent duplicate requests yielding exactly one current token/job. Exercise the race with independent database connections and deterministic synchronization.
- [x] Run focused tests and confirm failures before implementation.
- [x] Implement bounded configuration parsing and discard raw extradata before persistence. Add the explicit refresh entry point through the existing inspection lifecycle; preserve current revision/token protection.
- [x] Verify old inspection records, refreshed facts, stale worker completion rejection and unchanged scan atomicity through PostgreSQL tests, including `mix test test/bolognesa/libraries/request_inspection_refresh_test.exs`; review and commit `feat(playback): define exact source configurations`.

## Task 3 — Pure candidates, reports and selection

**Create:** Playback domain candidate and delivery-plan value objects, policies for candidates/negotiation and a capability-report value object. **Modify:** `domain/policies/transcode_strategy.ex`; add corresponding tests under `test/bolognesa/playback/`.

**Interfaces:** candidate generation consumes `Source.t()` and preference; returns at most six server-owned candidate configurations. Report validation consumes string-keyed report plus issued candidates and generation; returns typed results or bounded invalid-report error. Selection consumes source, candidates and validated observations; returns a typed plan or metadata/unsupported result.

- [ ] Write failing tests covering all five action combinations, exact output properties, silent video, HDR/unknown-color rejection, muxer restrictions, and direct default-track ambiguity.
- [ ] Add validation failures for unknown versions/fields/enums, duplicate/unissued IDs, 65-byte tokens, seven results and reports over 8 KiB; missing results remain unknown.
- [ ] Confirm failures, implement the pure policies and closed validation without input-derived atoms, then run the focused tests.
- [ ] Require deterministic cheapest eligible selection and no unsafe candidate creation; review and commit `feat(playback): negotiate validated delivery plans`.

## Task 4 — Execute independent stream actions

**Modify:** `playback.ex`, application playback use cases, `infrastructure/ffmpeg_args.ex`, `transcode_manager.ex`, `domain/read_models/transcode_session.ex`, session diagnostics/telemetry allowlists and existing FFmpeg/manager tests.

**Contract:** preparation consumes an authorized typed plan, revalidates the source and binds revision/indexes/actions/transport to the session. Seek replaces the session using that plan rather than source-only strategy selection. FFmpeg arguments accept no raw client values.

- [ ] Add failing argument tests asserting copy/copy, copy/AAC, H.264/copy, H.264/AAC and absent-audio behavior, absolute mappings and exact encoder bounds.
- [ ] Add manager tests for stale revision, unsupported plans, busy sessions and cleanup without process/directory creation on invalid input; confirm failures.
- [ ] Implement plan execution, codec-specific filters and updated bounded enum allowlists. Retain existing authentication/controller checks.
- [ ] Run `mix test test/bolognesa/playback` and relevant transcode-controller/observability tests; review and commit `feat(playback): execute minimal stream transformations`.

## Task 5 — Browser and LiveView capability exchange

**Create:** `assets/js/video/player/playback_capabilities.mjs` and its Node tests. **Modify:** `video/hooks/video_player.js`, `player/source_controller.mjs`, `controllers/hls.mjs`, `lib/bolognesa_web/components/player.ex`, LiveSupport playback modules and movie/episode playback reducers/templates.

**Contract:** a mounted stable frame receives generation/candidate configurations without a source URL. Browser reports the version-1 contract within three seconds. Server ignores stale/duplicate resolved generations and starts delivery only after fresh authorization/selection. The HLS controller honors the chosen native/HLS.js transport.

Add an explicit `:checking` playback phase separate from selected-file identity. In `Player.player/1`, render the frame/video during checking, omit both `data-src` and native `video src`, and suppress autoplay until an accepted plan supplies a source. `Player.video_src/1` must no longer infer direct delivery solely from `transcode_session == nil`. SourceController must skip attachment and source-recovery effects while checking. Keep the frame and ignored UI ancestors mounted across checking, preparing, ready and error states; clearing a previous source must not recreate the elements. Remove task 4's temporary source-only adapter when all movie/episode/part callers use negotiation.

- [ ] Add failing Node tests for exact file probes, `maybe`, rejected/missing Media Capabilities, deadline, missing dimensions, MSE support and inferred native HLS support.
- [ ] Add failing shared-component/LiveView tests that checking renders a mounted hook with neither `src` nor `data-src`, no autoplay and no FFmpeg session; include initial render and version/part changes. Cover stale reports after version/episode changes, malformed reports and duplicate accepted reports.
- [ ] Add a real-browser request assertion: hold the capability response, assert zero media/playlist/segment requests while checking and unchanged frame/video identity, then release the report and assert delivery begins only for the accepted selection. Test the three-second timeout without silently attaching the original.
- [ ] Implement video-owned probing and lifecycle wiring; expose localized checking, metadata-required, unsupported and preparing states plus explicit refresh/original actions. Wire every automatic continuation through negotiation.
- [ ] Run Node and affected movie/episode LiveView tests; verify stable player ancestors. Review and commit `feat(playback): report browser capabilities before delivery`.

## Task 6 — One recovery per attempt

**Modify:** LiveSupport playback state/events/control, browser source controllers and recovery modules; extend their existing tests and translated feedback.

**Contract:** correlated current decode/media errors may transition once to an eligible positively tested compatible output at validated position. Network/autoplay/authorization/source/server failures do not trigger conversion. Seek, temporary reconnect and same-attempt restoration preserve budget; explicit Play/Retry or new LiveView process creates a new attempt.

- [ ] Add failing tests for duplicate/stale errors, failed compatible output, HDR direct failure, negative/oversize positions, network failures, autoplay rejection and recovery followed by seek/reconnect.
- [ ] Implement attempt generation, budget, source-safety recheck and terminal feedback; never cycle back to a failed cheaper plan.
- [ ] Run relevant ExUnit and Node tests plus the production-hook recovery harness; review and commit `fix(playback): bound capability recovery to one attempt`.

## Task 7 — Real output and browser acceptance

**Modify:** existing scripts under `scripts/playback/` and browser fixtures/tests; temporary media and reports belong under `tmp/`.

- [ ] Generate synthetic direct MP4, H.264/AAC MKV, H.264/AC-3, incompatible video/AAC, both-stream conversion, silent and false-report fixtures with actual FFmpeg.
- [ ] Inspect actual output codecs/profile/pixel format/mappings with ffprobe; verify copied stream packet equivalence where practical and compare matched remux/full-conversion CPU observations.
- [ ] Exercise the real LiveView and FFmpeg path in desktop Chrome: startup, seek, pause/resume, EOF, fallback, episode/part continuation and fullscreen stability. Test native HLS separately where available.
- [ ] Run `node --test assets/test/*.mjs`, relevant browser harnesses and `sh scripts/dev/local.sh test`; require zero failures or record precise blockers. Use native setup/server; confirm Tidewave instance before runtime inspection. Do not start Docker automatically.
- [ ] Record a sanitized matrix in #10 with actual browser/device versions. Keep physical Chrome-on-iPhone acceptance pending until actually tested; emulation does not satisfy it.

## Task 8 — Document implemented limits and final review

**Modify:** decision 0011, README playback limits, CHANGELOG and overlapping Task 6 in `hls-playback-optimization-plan.md`.

- [ ] Update documentation to the implemented subset, including inspection refresh, unknown detection, output restrictions and actual device coverage.
- [ ] Review the full diff for privacy, closed input contracts, per-request authorization, source lifecycle, enum completeness and copied-stream correctness.
- [ ] Run required checks after any review fixes; record actual commands/results, branch and pending device verification in #10 or the PR.
- [ ] Remove completed temporary design/plan notes or distill durable contracts. Keep #10 open if acceptance evidence remains missing. No deployment.

Self-review: every approved design section maps to tasks 0–8. Real output verification precedes the encoded probe contract; candidate/report/plan types precede consumers; metadata refresh has an authorized atomic API; the shared player owns the no-source checking phase. Legacy records, metadata safety, lifecycle races and native transport have explicit test ownership. No task assumes automated tests establish iPhone compatibility.

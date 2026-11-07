# Capability-based playback implementation plan

> Execute with `superpowers:executing-plans`, one task at a time, using native development. This temporary plan follows the approved [design](playback-negotiation.md).

**Goal:** choose direct, remux, audio conversion or video conversion from validated client reports and authorized source facts.

**Architecture:** Libraries owns inspection facts. Playback owns candidates, report validation and delivery plans. LiveView owns negotiation generations and attempt budgets; video modules probe server configurations and consume the selected transport.

**Stack:** Elixir/Phoenix, PostgreSQL, FFmpeg, Video.js, hls.js, ExUnit, Node and existing Playwright harnesses.

## Global constraints

Preserve per-request authorization/revision/source checks, read-only originals, one FFmpeg session, five-minute idle expiry, 512 MiB storage bound, 12-second preparation and four-second segment target. Reports allow six results, 8 KiB, 64-byte tokens and a three-second detection deadline. Generated video is SDR H.264 High 4.1, 8-bit 4:2:0, at most 1920x1080/30 fps, CRF 25, ultrafast, two threads, 8 Mbps VBV maximum/16 Mbit buffer. Generated AAC-LC is 128 kbps, 48 kHz, at most stereo. No HDR tone mapping, HEVC HLS, dependency upgrade or deployment.

## Review focus

- Legacy inspections and missing color facts must not enable unsafe conversion (tasks 1–3).
- Default versus explicitly mapped tracks must agree with the probed configuration (tasks 1–4).
- Late browser reports and errors must not replace a newer selection (task 5).
- Seek/reconnect/checkpoint restoration must retain the current attempt's fallback budget (task 6).
- Native HLS and silent media must work without assuming desktop Chrome proves iPhone support (tasks 4, 7).

## Task 1 — Persist bounded negotiation facts

**Modify:** Libraries `domain/value_objects/inspection/technical_track.ex`, `infrastructure/services/ffprobe_media_probe.ex`, `ffprobe_json.ex`, `infrastructure/repositories/ecto_inspection_repository/inspection_mapper.ex`; Playback `domain/read_models/technical_track.ex` and `infrastructure/repositories/ecto_playback_repository.ex`.

**Contract:** additive optional fields for original stream index, default/attached-picture dispositions, profile/level, pixel format/bit depth, dimensions, rational frame rate, bitrate, sample rate/channels and color facts. Legacy JSON loads with unknown values. Retain normalized fields only; raw probe output never becomes diagnostics.

- [ ] Add failing parser/mapper/projection tests for legacy JSON, malformed optional facts, attached pictures, original indexes and unknown color metadata.
- [ ] Run `mix test test/bolognesa/libraries/ffprobe_json_test.exs test/bolognesa/libraries/ffprobe_media_probe_test.exs` in the native worktree environment; confirm the new assertions fail.
- [ ] Extend validation, ffprobe entries and both context-owned projections; preserve the 256 KiB/128-stream limits.
- [ ] Run the focused tests and repository round-trip tests; require zero failures. Review and commit `feat(playback): retain bounded negotiation facts`.

## Task 2 — Exact codec identifiers and metadata refresh

**Create:** Libraries inspection codec-configuration parser beside `ffprobe_json.ex`; Playback domain candidate and delivery-plan value objects. **Modify:** Libraries inspection request use cases/facade and the modules from task 1.

**Contract:** codec parser returns a validated RFC 6381 identifier or unknown. Playback plan carries selected absolute stream indexes, delivery, independent stream actions, output envelope, transport and bounded reason. Select first non-picture video and first audio by index, with optional audio. An authorized explicit metadata refresh schedules existing durable inspection once per action without changing file identity.

- [ ] Add failing AVC/HEVC configuration-record tests, truncated/oversize data tests, default-track mismatch and duplicate-refresh tests.
- [ ] Run focused tests and confirm failures before implementation.
- [ ] Implement bounded configuration parsing and discard raw extradata before persistence. Add the explicit refresh entry point through the existing inspection lifecycle; preserve current revision/token protection.
- [ ] Verify old inspection records and refreshed facts through PostgreSQL tests; review and commit `feat(playback): define exact source configurations`.

## Task 3 — Pure candidates, reports and selection

**Create:** Playback domain policies for candidates/negotiation and a capability-report value object. **Modify:** `domain/policies/transcode_strategy.ex`; add corresponding tests under `test/bolognesa/playback/`.

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

**Create:** `assets/js/video/player/playback_capabilities.mjs` and its Node tests. **Modify:** `video/hooks/video_player.js`, `player/source_controller.mjs`, `controllers/hls.mjs`, LiveSupport playback modules and movie/episode playback reducers/templates.

**Contract:** a mounted stable frame receives generation/candidate configurations without a source URL. Browser reports the version-1 contract within three seconds. Server ignores stale/duplicate resolved generations and starts delivery only after fresh authorization/selection. The HLS controller honors the chosen native/HLS.js transport.

- [ ] Add failing Node tests for exact file probes, `maybe`, rejected/missing Media Capabilities, deadline, missing dimensions, MSE support and inferred native HLS support.
- [ ] Add failing LiveView tests for no premature media/FFmpeg attachment, stale reports after version/episode changes, malformed reports and duplicate accepted reports.
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

Self-review: every approved design section maps to tasks 1–8. Candidate/report/plan types are defined before consumers; legacy records, metadata safety, lifecycle races and native transport have explicit test ownership. No task assumes automated tests establish iPhone compatibility.

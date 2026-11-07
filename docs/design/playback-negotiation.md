# Capability-based video playback negotiation

Status: design approved for [issue #10](https://github.com/avillen/bolognesa/issues/10); implementation pending. The implementation-plan review corrected the requested versus actual encoder-profile assumption below. No playback behavior has changed.

## Intent and scope

Choose the least expensive delivery the selected browser reports it can play. The owner's priority is **Chrome on iPhone**. Exact device, iOS and Chrome versions and physical-device results remain unknown. Detect runtime features rather than inferring them from the browser name.

Retain Phoenix, Video.js, hls.js, the native HLS branch and the single FFmpeg session manager. Support direct play, remux, audio conversion and video conversion, with audio converted independently only when needed. Music playback is outside this change.

The defaults and numerical bounds below are proposed engineering choices, not preferences already approved by the owner. This is a project requiring an implementation plan after design approval.

## Current behavior and dependencies

At `faf2843`, `TranscodeStrategy.choose/1` handles two source-only exceptions and otherwise chooses direct playback. Its previous name in the issue, `TranscodeProfile`, is stale. `Playback.prepare_video/3` starts delivery before receiving any client capabilities. A direct error requests H.264/AAC conversion; HLS errors terminate playback.

Libraries inspection retains codec, dimensions, channels and language. Playback projects only kind and codec. Stream indexes, profile, level, pixel format and frame rate are missing. `FfmpegArgs` always selects the first video/audio streams and always encodes audio to AAC. New negotiation must change the projection and FFmpeg mapping together.

This overlaps Task 6 of the existing [HLS optimization plan](hls-playback-optimization-plan.md). Issue #10 owns capability negotiation and remux; reuse that task's FFmpeg/browser evidence gates rather than implementing a second source-only remux rule. Pause polling, segment delivery and buffered-seek optimizations remain separate work. There is no milestone assigned to #10; the only existing milestone is the closed experimental-preview milestone.

## Source facts and track selection

Extend Libraries' bounded ffprobe result, value object, JSON mapper and Playback projection with original stream index, profile, level, pixel format/bit depth, dimensions, rational frame rate, bitrate, audio sample rate/channels, attached-picture disposition and color-transfer/primaries information. Unknown, missing and invalid optional fields become unknown; they must not create false support claims or reject otherwise valid legacy inspections.

Build standards-compliant codec identifiers from validated codec configuration where possible. Do not invent an AVC or HEVC codec string from a codec name alone: exact AVC constraint flags and HEVC compatibility fields matter. If configuration data is required, request bounded extradata through the existing bounded probe, parse only supported configuration records and discard raw bytes before persistence. Keep the existing 256 KiB output and 128-stream limits. An unrecognized configuration remains unknown. Libraries owns extraction; Playback owns delivery compatibility.

Keep additive normalized fields in the existing inspection JSON, without replacing file identities or requiring a schema migration. Legacy records remain readable. Add an explicit, authorized inspection refresh through Libraries' existing durable inspection mechanism for missing negotiation metadata; bound concurrent requests and avoid a rescan/reinspection loop on every page load. Detailed refresh use-case wiring belongs in the implementation plan.

For this delivery, select the first non-attached-picture video and first audio by original stream index; allow silent video. There is no new audio selector, subtitle burn-in, alternate rendition or streaming-quality UI. Bind these selected indexes to the plan and use absolute `-map 0:<index>` arguments, with no audio map for silent video. Direct play is eligible only when the original's effective default tracks match this selection and no extra unsupported tracks introduce ambiguity; otherwise select a controlled HLS output. Subtitles remain disabled in generated HLS.

Direct-file probing can cover exact known MP4/MOV, WebM and Matroska configurations. Codec identifiers unsupported by the initial parser are unknown, even if the codec family is recognized. The initial HLS output envelope remains **MPEG-TS, SDR H.264 8-bit 4:2:0, AAC-LC at up to two channels**; copy only streams that fit that envelope and pass the client test. This intentionally bounds the muxer and player work. HEVC can play directly with an exact positive report, but HEVC-in-HLS/fMP4 remux requires later work. Do not claim generic HEVC/HDR support.

HDR or Dolby Vision sources without positively supported direct playback receive a specific unsupported-conversion message; do not silently convert them to incorrect SDR colors. Tone mapping is outside scope. Unknown profile/color metadata cannot establish safe copying or safe SDR conversion. Apply these source-safety checks when creating candidates and again during recovery. Refresh missing metadata at most once per explicit inspection-refresh action. If required facts remain unknown, show a terminal metadata-incomplete state, without automatic refresh or conversion; retain a separately labelled, explicit best-effort original-file attempt. Automatic negotiation must not revert to direct-first for every unknown source. The authorized direct-delivery endpoint remains usable without inspection, as required by the current backend convention.

## Capability exchange

Use source-specific probes, rather than a permanent codec matrix or an unbounded browser fingerprint. Before attaching a media URL or starting FFmpeg:

1. Authorize the selected movie/episode/file and load its current revision and selected tracks.
2. Issue an opaque generation token and at most six server-owned candidate configurations: original, HLS copy/copy, copy/AAC, H.264/copy, H.264/AAC, and H.264 without audio where applicable. Candidates contain normalized playback facts and MIME/codec strings only, never paths, titles, credentials or media URLs.
3. A video-owned browser module probes these configurations and reports bounded results through LiveView. It runs on a mounted player frame without attaching a source. Keep the element mounted through checking, preparation and source replacement.
4. Validate results, match the generation and revision, reauthorize/revalidate the source and run the domain policy. Only then attach direct delivery or start the chosen HLS session.

Wire report, version-selection and automatic episode/part continuation through the same path. A late result for a previous version, revision, LiveView or generation cannot change playback. Store capability results only for the current selection in socket/browser memory; clear on source change and reload. A seek reuses the accepted plan and selected tracks, with current authorization/revision validation, rather than renegotiating back to a cheaper failed strategy.

Version 1 report shape:

```json
{
  "version": 1,
  "generation": "server-issued-opaque-token",
  "preference": "auto",
  "results": [
    {
      "candidate_id": "server-issued-candidate-id",
      "transport": "file",
      "support": "supported",
      "smooth": "unknown",
      "power_efficient": "unknown"
    }
  ]
}
```

Allow `transport` only as `file`, `native_hls` or `hls_js`. Support and the optional performance observations are three-valued enums: `supported`/`unsupported`/`unknown` for support, `yes`/`no`/`unknown` for performance. Preference is `auto` or `compatible`; expose compatible playback as an explicit recovery action rather than an account setting. `auto` minimizes transformations; `compatible` requests the tested H.264/AAC candidate. Performance observations aid diagnostics but do not override positive support or trigger arbitrary quality changes in this version.

Reject unknown versions, extra fields, duplicate/unissued candidate IDs, contradictory transports, invalid enums, more than six results, tokens longer than 64 bytes or a report over 8 KiB. Missing results are unknown. Keep token-to-candidate associations server-owned; a report cannot provide an FFmpeg argument, stream index, source fact, codec string or URI. Never create atoms from input. Malformed reports produce bounded feedback and no FFmpeg launch. Duplicate valid reports are idempotent. Ignore reports after the generation is resolved.

Set a three-second aggregate detection deadline; API rejection, timeout, absent APIs and uncertain MIME results produce unknown, not false certainty. When the report/deadline contains no positively supported candidate, show a useful detection/unsupported state with explicit retry and best-effort original actions. Do not start a source-only conversion when the client cannot establish it can consume the output.

## Detection and transport limits

For original files, use `canPlayType` with the exact MIME and codecs. An empty answer rejects the candidate; `maybe` is unknown. When complete dimensions/bitrate/frame-rate or audio configuration are available, consult `MediaCapabilities.decodingInfo` with `type: file`; a supported answer strengthens a positive exact MIME result. Explicit rejection wins. A positive exact `probably` result can stand when Media Capabilities is absent or inconclusive. Do not treat missing bitrate as zero or a generic MIME response as proof of a profile.

For hls.js, require its runtime support plus MediaSource codec support for the fragmented MP4 the pinned library actually produces, and restrict candidates to its tested MPEG-TS demux envelope. For native HLS, require native HLS MIME support and a positive exact elementary-stream decoding test; there is no general browser API that proves a particular HLS playlist will play. Mark that combination as inferred support in local diagnostics and validate it with actual generated streams.

Select a transport per candidate. Preserve the existing hls.js-first order where both paths qualify; native HLS is used when it is the qualifying path. The controller must honor the server-selected transport rather than independently choosing another branch. No user-agent allowlist and no assumption that desktop Chrome proves Chrome-on-iPhone compatibility.

Detection is advisory and can be wrong. `canPlayType` describes likelihood, and Media Capabilities predicts decoding rather than testing delivery. See the [HTML media standard](https://html.spec.whatwg.org/multipage/media.html#dom-navigator-canplaytype), [Media Capabilities draft](https://www.w3.org/TR/media-capabilities/) and [Apple HLS authoring specification](https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html). These APIs do not certify end-to-end HLS, network throughput or server conversion speed.

## Server decision and FFmpeg execution

Represent the result with a Playback-owned typed plan: delivery, selected stream indexes, independent video/audio actions, output envelope, chosen transport and bounded reason. Keep the compatibility policy pure; application use cases authorize, load and execute it. Web reducers never choose codecs.

Apply this order only to eligible, positively supported candidates:

| Delivery | Video action | Audio action | Example |
| --- | --- | --- | --- |
| Direct | Original | Original | Supported original MP4 |
| Remux | Copy | Copy/absent | H.264/AAC MKV to tested HLS output |
| Audio conversion | Copy | AAC | Supported H.264 with unsupported AC-3 audio |
| Video conversion | H.264 | Copy/absent | Unsupported video with supported AAC |
| Video and audio conversion | H.264 | AAC | Both selected streams need conversion |

Video conversion is more expensive than audio conversion; choose copying supported audio before encoding it. A supported codec outside the current output envelope cannot automatically be copied into MPEG-TS. Return a bounded reason distinguishing client rejection, missing metadata and output-envelope restrictions. Unsupported sources do not create arbitrary additional candidates.

Generated video uses the existing ultrafast/CRF-25/two-thread encoder settings, SDR 8-bit 4:2:0 output, and at most 1920x1080 and 30 fps without upscaling. Target H.264 Constrained Baseline level 4.1, with an explicit baseline restriction; verify the actual SPS and codec identifier in an initial real-output experiment before fixing capability probes. A review encode using ultrafast and even an explicit High request produced Constrained Baseline, so the requested profile name cannot establish the advertised stream configuration. Add an 8 Mbps VBV maximum and 16 Mbit buffer; probe the planned dimensions/frame rate with 8 Mbps as the conservative video bitrate. Candidate tests describe that actual verified configuration. Keep AAC-LC output at 128 kbps, 48 kHz and at most stereo. Copy AAC only when its profile, channel and sample-rate constraints fit the tested output. Keep original dimensions/frame rate when copied. Reject conversion when the output candidate is unsupported.

Extend `FfmpegArgs` to take the validated plan, not raw client input. Add pure copy/copy and H.264/copy arguments, codec-specific bitstream filters only where required, and silent-video handling. Verify actual codecs with ffprobe, including packet equivalence for copied streams where practical. Keep sliding MPEG-TS, seek offsets, session ownership, temporary cleanup, 12-second preparation, four-second segment target, five-minute idle expiry, 512 MiB storage cap and single global session. Longer copied GOPs still require explicit playback/startup verification.

## Bounded recovery and feedback

Maintain a server-owned attempt generation and one automatic recovery budget per selected source/revision. Direct errors and fatal HLS errors carry that generation plus current file/session correlation and a bounded position. Reject stale, duplicate and out-of-range reports.

If an initially selected direct/remux/partial-conversion plan fails to decode or consume its media, allow one automatic transition to the positively tested compatible H.264/AAC output (H.264-only for silent video) at the accepted position. Do not retry when already using that output, and do not consume this path for authorization failures, source invalidation, server busy, missing FFmpeg, network failures or autoplay rejection. Terminal HLS/network errors remain visible; autoplay rejection asks for a user gesture.

The recovery may encode streams previously believed supported because the report was contradicted by real playback, provided source-safety eligibility still allows conversion. HDR or incomplete color facts remain terminal if direct playback fails. Recovery never cycles back to direct/remux. Seek, pause/resume, temporary socket reconnection, checkpoint restore within the current attempt and a refreshed capability report do not replenish the budget. A deliberate new Play/Retry action starts a new attempt; provide clear feedback when that action is required. A full document reload or new LiveView process also starts a new attempt and repeats negotiation; the checkpoint restores position/pause intent only, not a trusted recovery budget. Do not introduce automatic page reloads. This bounds recovery per server-owned attempt without adding durable attempt storage. Preserve the stable player/fullscreen elements and existing same-tab recovery, continuation and media coordination.

Show localized states for checking compatibility, preparing playback, recovering once, unsupported output and terminal failure. Expose concise mode/reason text alongside playback status. Add fixed telemetry reason/strategy/transport enums and update all allowlists together. Never log full reports, MIME strings, UA, paths, titles or extradata; no identifying metric labels. Generation/session/file IDs may appear only in validated local correlation logs.

## Implementation boundaries and acceptance

An implementation plan should group work into independently reviewable changes:

1. Inspection facts, legacy decoding and explicit durable metadata refresh; typed Playback projection and selected-track contract.
2. Pure candidate/plan policy, closed client report validation and independent FFmpeg actions.
3. LiveView/browser negotiation lifecycle, selected HLS transport, bounded recovery and localized feedback.
4. Actual FFmpeg fixtures and browser verification; update decision 0011, README limits, changelog and the HLS plan's overlap only for implemented behavior.

Likely files include the existing Libraries inspection modules/mappers, `playback/domain/policies/transcode_strategy.ex`, Playback read models and facade/use cases, `ffmpeg_args.ex`, `transcode_manager.ex`, observability allowlists, shared LiveSupport playback modules and movie/episode reducers/templates. Browser work belongs under `assets/js/video/` with hook wiring in `video/hooks/video_player.js`. Extend existing ExUnit/Node/Playwright harnesses; avoid unrelated refactors or dependency upgrades.

Cover decision combinations, unknown/false reports, malformed bounds, optional audio, track ordering, old inspections, stale revisions/generations, duplicate errors, preserved recovery budget through seeks/reconnects, and failure after recovery. Re-run adversarial authorization, revocation, missing/changed source, same-actor replacement and cleanup tests. Test unsupported outputs without creating a process or temporary directory.

Run focused tests, `node --test assets/test/*.mjs`, native `sh scripts/dev/local.sh test` (which runs `mix precommit`), real-FFmpeg codec checks and production-hook browser tests. Verify real LiveView negotiation/continuation and stable fullscreen, not only mocked hook events. Use native setup/server and confirm Tidewave's instance before relying on runtime results; no automatic Docker startup. The screenshot workflow's Docker prerequisite requires an explicitly available environment; record any unrun UI checks.

Acceptance requires a sanitized matrix with source container/codec/profile, selected strategy/transport, browser/device versions and actual start, seek, pause/resume, EOF, fallback and continuation results. Include direct MP4, H.264/AAC MKV remux, H.264/AC-3 audio conversion, incompatible video/AAC video-only conversion, both-stream conversion, silent video and one intentional false report. Compare copied-output CPU against full conversion for matched synthetic fixtures without inventing savings.

Prioritize physical Chrome-on-iPhone checks, then desktop Chrome as a separate baseline. Playwright mobile emulation or WebKit automation does not complete the iPhone item. If the phone is unavailable, complete independent implementation/checks, record the remaining device check in #10 and keep that acceptance item open. Never close the issue or imply device compatibility from unit tests. No deployment is part of this design.

After implementation, remove this temporary design or distill lasting contracts into decision 0011 and conventions. Issue/PR comments own verification evidence and pending steps.

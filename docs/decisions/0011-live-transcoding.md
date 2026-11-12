# 0011. Capability-based video playback

Status: implemented for [#10](https://github.com/avillen/bolognesa/issues/10). Desktop Chrome/HLS.js checks and a local WebKit native-HLS fixture pass; physical Chrome on iPhone remains unverified. Deployment evidence belongs in the issue, independently of device acceptance.

## Context

Source-only container/codec exceptions and conversion after any native error caused unnecessary encoding and could not establish that a browser could consume the result. Capability predictions can also be inaccurate, and a failed download may look like an unsupported format.

## Decision

Authorize the selected movie/episode/file and issue source-specific candidate configurations before attaching a media URL or starting FFmpeg. A generation binds at most six candidates to the current source revision. Candidates contain normalized decoding facts and exact codec identifiers, never URLs, paths or arbitrary encoder arguments.

Libraries retains bounded optional stream facts in the existing inspection JSON. AVC/HEVC identifiers come from recognized bounded configuration records; AAC-LC comes from its supported configuration record. Raw extradata is discarded. Missing or malformed facts remain unknown. Exact recognized pixel formats can supply missing sample depth; contradictory declarations remain unknown. Existing inspections remain readable, but may require an explicit authorized inspection refresh. Refresh coalesces a current pending request and applies a 30-second cooldown to terminal-request repetition; it does not trigger automatically on page load. The UI permits one refresh request per explicit playback action and reports when it was accepted.

Select the first non-attached-picture video and first audio by original absolute stream index; audio is optional. Native original delivery requires an unambiguous selected/default-track combination. Controlled HLS maps only the selected streams, without subtitles or data streams. No track selector, subtitle burn-in or quality ladder is introduced.

### Capability contract and selection

Version 1 reports contain only the issued generation, `auto` or `compatible` preference, and bounded candidate results. Transports are `file`, `hls_js` or `native_hls`; support is `supported`, `unsupported` or `unknown`. Optional smoothness and power-efficiency observations are `yes`, `no` or `unknown`. Reject extra fields, invalid enums, duplicate/unissued candidates, invalid transports, tokens over 64 bytes, more than six results or reports over 8 KiB. Never create atoms from input.

The browser probes exact MIME/codec configurations with a three-second aggregate deadline. `canPlayType` must return `probably` for original files; `maybe` is unknown. Optional complete Media Capabilities results can veto or strengthen that prediction. Missing bitrates are not replaced with zero. HLS.js requires its runtime support and exact fragmented-MP4 MediaSource support for the generated MPEG-TS streams. Native HLS recognizes a generic playlist MIME response of `maybe` or `probably`, but still requires `probably` for the exact MP4 elementary-stream codecs. A missing/throwing API remains unknown; this is inferred eligibility, not proof of playlist playback. HLS.js remains preferred when both transports qualify. The controller honors the accepted transport.

The server allows five seconds for an unresolved generation, including transport/scheduling overhead. It reauthorizes and reloads the source, validates the closed report, then chooses the cheapest positively supported eligible plan:

| Delivery | Video | Audio |
| --- | --- | --- |
| Original | Original | Original/absent |
| Remux | Copy | Copy/absent |
| Audio conversion | Copy | AAC-LC |
| Video conversion | H.264 | Copy/absent |
| Full conversion | H.264 | AAC-LC |

Video encoding requires known SDR color facts. Stream copy preserves the encoded video and may retain absent color facts; explicitly unsupported color declarations, including HDR transfer functions and BT.2020 primaries/matrices, still exclude this path. Copied video is restricted to exact H.264 Constrained Baseline or Main at level 4.1 or below, yuv420p/8-bit, at most 1920×1080 and 30 fps. Known average video bitrates over 8 Mbps exclude copying. Matroska often omits average bitrates; absent bitrates remain unknown and do not alone force encoding when the remaining envelope and client probe qualify. Neither an average bitrate nor a decoding prediction guarantees network throughput. Copied AAC must be exact AAC-LC, mono/stereo at 32, 44.1 or 48 kHz.

Generated video uses ultrafast/CRF 25, two threads, Constrained Baseline level 4.1, SDR yuv420p/8-bit, an 8 Mbps VBV maximum and 16 Mbit buffer, and at most 1920×1080/30 fps without upscaling. Scaling preserves display aspect ratio, including anamorphic sources. Generated AAC-LC is 128 kbps, 48 kHz stereo. The actual AVC configuration is `avc1.42C029`; the requested profile name alone is not evidence. HEVC originals require exact positive browser support; known-SDR HEVC can instead be encoded to H.264. HEVC stream copy into HLS/fMP4, HDR/Dolby Vision conversion and tone mapping are outside this envelope. Unknown required color/profile facts cannot establish safe video encoding. Copying retains the original exact codec identifier and still requires a positive browser probe; it does not infer missing color declarations or promise decoder support.

No positive candidate produces a terminal detection/metadata/unsupported state. The user can retry detection, request inspection refresh, or deliberately try the original without a compatibility promise. An available positive compatible candidate also enables an explicit compatible-playback action, including in fullscreen feedback. These are per-attempt actions, not account preferences.

### Recovery and delivery lifetime

Each new Play/Retry has a separate server-owned attempt UUID and one automatic recovery budget. Native decode errors (code 3) and fatal HLS.js media errors can select the positively reported compatible H.264/AAC output once, reauthorizing and rechecking source safety at the bounded whole-file position. Native code 4 is unknown: an actual failed download can produce it. Network, authentication, source, busy/tool, autoplay and unknown failures do not automatically start conversion. A failure of compatible output is terminal. Recovery never cycles back to original/remux.

Correlate failures with the current attempt, selected file/session, ready phase and valid position. Ignore stale/duplicate/malformed events. Seek, expired-session resume and temporary reconnect retain the plan and budget; terminal playback requires an explicit action. Deliberate original playback starts a fresh identity with automatic conversion disabled. A reload/new LiveView repeats negotiation; same-tab checkpoints restore position/pause intent, not trusted recovery state.

FFmpeg accepts a validated typed source-derived plan, with absolute stream maps and independent copy/encode actions. Revalidate the current plan before process/directory creation. A supervised manager admits one shared session; another actor receives busy, and same-actor replacement remains intentional. Sessions bind actor, typed content reference, file and revision. Preserve five-minute idle expiry, 512 MiB temporary-storage bound, a 12-second preparation deadline and private directory cleanup. Originals remain read-only.

Authenticate every playlist/segment request and recheck role/session revocation, association, revision, source availability and generated segment names. FFmpeg reopens the input path after validation, so external source replacement remains a race; read-only mounts prevent Bolognesa writes, not external changes.

HLS uses a sliding MPEG-TS playlist with 12 entries, a four-second target and two retained deleted segments. An initial 12-second unpaced read burst remains separate from startup readiness, then input remains paced. Readiness requires at least one complete segment and four seconds of published duration, or a nonempty completed playlist near EOF. Every referenced segment must exist. The preparation deadline is sixty seconds; copied segments between four and twelve seconds can start without waiting for the next GOP. Server readiness does not guarantee immediate browser playback: native HLS may wait for more data. The smaller startup cushion reduces tolerance of slow production or delivery and does not guarantee uninterrupted playback. Copied GOPs can make longer segments. hls.js starts at the generated session's beginning with a three-segment synchronization distance. Pause suspends FFmpeg; committed seeks replace the session at the requested offset.

### Player and diagnostics

Video.js 10.1.0 owns controls through the vendored HTML build; hls.js owns the selected JavaScript transport. The native video decodes media. A time/buffer adapter presents full-file time and seek range. Drag previews do not start FFmpeg. LiveView owns outer source/session attributes; JavaScript owns an ignored stable inner subtree. Checking, preparation, failure, replacement and episode/part continuation retain the player and skin so supported element fullscreen survives. Entering fullscreen again after a reload still requires user action; native mobile fullscreen needs separate verification.

The vendor bundle/license and English/Spanish controls remain local. Rebuild with `npm ci` and `npm run vendor-videojs`. The scoped time-format adapter preserves browsers that reject `Intl.NumberFormat` unit style, without implying device compatibility.

Strategy, transport and selection-reason telemetry uses closed enums and existing sanitized emitters. Automatic LiveView parameter logging is disabled for the movie and episode player views so rejected reports cannot be logged before validation. Reports, MIME strings, user-agent strings, paths, titles and extradata are not diagnostic labels. Validated IDs are for local correlation only. Performance observations do not override positive support or select arbitrary quality levels.

Preparation logs record prelaunch validation/setup and previous-session cleanup separately from process-spawn time. Elapsed preparation time starts after the process port opens. FFmpeg supplies numeric progress reports once per second; only the first report and snapshots at the first observed segment, readiness, or timeout produce observations. Snapshots include the reported frame count, output timestamp, speed, first-report latency, and latest-report age when available. Missing progress is omitted, not recorded as zero. Output timestamps and speed describe FFmpeg processing, not input throughput or playable browser buffer. Readiness observations follow the existing polling schedule; they do not measure precise publication times or prove that listed segments were readable at timeout. The first progress report can contain zero frames and does not establish when input reading began. These measurements narrow the investigation but do not identify disk, network, CPU, or decoding delays by themselves. Only bounded numeric progress fields are retained; raw tool output, media paths, and titles are discarded.

## Consequences and verification limits

The bounded envelope trades some avoidable encoding for explicit, testable output. Optional missing metadata can require user refresh. Advisory support can still be wrong, and ambiguous native errors require deliberate compatible playback rather than speculative automatic conversion.

Actual source-derived FFmpeg/ffprobe checks cover independent actions, silent media, AVC configuration and copied video/AAC payloads. The native desktop LiveView matrix covers startup, controls, seek, actual download abort, explicitly injected capability/media errors, natural part/episode EOF and fullscreen identity. Controlled original rejection exercises HLS paths; it is not evidence Chrome naturally rejects each original. These checks do not certify native HLS, physical iPhone playback, Linux process cleanup, every source profile or target-server real-time capacity. Keep format/device evidence and pending acceptance in [#10](https://github.com/avillen/bolognesa/issues/10), and runnable checks in the [playback verification guide](../playback-testing.md).

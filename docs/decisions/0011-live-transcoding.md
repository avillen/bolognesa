# 0011. On-demand compatible playback

Status: HLS delivery implemented and deployed; Video.js controls implemented locally. Performance and playback quality must be verified on the target server and clients.

## Context

Direct playback worked for a compatible MP4 but browser tests showed that some audio and video combinations could not be played. The owner requested an on-demand compatibility path.

## Decision

Use technical inspection to choose direct delivery, audio conversion with H.264 video copied, or conversion to H.264/AAC. For unknown profiles, try direct playback. A browser failure automatically starts full H.264/AAC conversion at the reported playback position for movies and episodes. Duplicate or stale direct-player errors do not restart conversion, and conversion failures remain visible without automatic retry. Browser autoplay restrictions can still require pressing play.

FFmpeg produces HLS MPEG-TS in a private temporary directory. A supervised `GenServer` owns the single allowed FFmpeg process. Sessions expire after five minutes of inactivity, cap fragments at 512 MiB, and clean up their temporary files. The original library remains mounted read-only; deployment scratch space uses tmpfs.

Authenticate every playlist and segment request and recheck actor, catalog/file relationship, revision, and source availability. Only application-generated segment names are accepted. The browser uses hls.js with native HLS as a fallback. Pause suspends FFmpeg; seeking restarts it at the requested position.

Preparation waits for at least 12 seconds of published segments, or a nonempty completed
playlist near the end of a file. FFmpeg may read an initial 12 seconds without pacing,
then retains real-time input pacing. The sliding playlist retains 12 entries, with a
four-second target per segment; copied video follows source keyframes and may produce
longer segments. hls.js starts at the beginning of each generated session and uses a
three-segment live synchronization distance. These settings provide a playback cushion
without continuously generating the file at unrestricted speed; they do not guarantee
real-time conversion on every server.

## Player controls

Movies and episodes use the vendored HTML build of Video.js 10.1.0 for controls, with
hls.js retained for compatible delivery. A time/buffer feature adapter presents the
original file's duration, current position, buffered ranges, and full seekable range.
Committed compatible seeks use the existing server event to replace FFmpeg's session;
drag previews do not start conversions. The native video remains responsible for decoding.

LiveView owns source/session attributes on the hook's outer frame. JavaScript owns an
ignored inner subtree and keeps the player and skin mounted across session changes,
including the preparing state. Mount the player before connecting its skin so controls
receive the player context. Native controls remain the initial HTML fallback.

The pinned dependency is rebuilt with `npm ci` and `npm run vendor-videojs`. Its bundled
module and license notices are checked in under `assets/vendor/`, so release builds and
browsers do not require npm or a CDN. English and Spanish controls are bundled locally.

## Consequences

The path adds temporary storage and a JavaScript dependency. FFmpeg reopens the original by path after validation, leaving a race that the process API cannot make atomic; read-only mounts prevent writes by Bolognesa, not external changes. Synthetic tests validate output codecs, not server capacity or device playback. See [FFmpeg's HLS muxer](https://ffmpeg.org/ffmpeg-formats.html) and [hls.js](https://github.com/video-dev/hls.js).

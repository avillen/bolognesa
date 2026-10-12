# 0011. On-demand compatible playback

Status: Implemented and deployed. Performance and playback quality must be verified on the target server and clients.

## Context

Direct playback worked for a compatible MP4 but browser tests showed that some audio and video combinations could not be played. The owner requested an on-demand compatibility path.

## Decision

Use technical inspection to choose direct delivery, audio conversion with H.264 video copied, or conversion to H.264/AAC. For unknown profiles, try direct playback and offer a compatible mode after a browser failure.

FFmpeg produces HLS MPEG-TS in a private temporary directory. A supervised `GenServer` owns the single allowed FFmpeg process. Sessions expire after five minutes of inactivity, cap fragments at 512 MiB, and clean up their temporary files. The original library remains mounted read-only; deployment scratch space uses tmpfs.

Authenticate every playlist and segment request and recheck actor, catalog/file relationship, revision, and source availability. Only application-generated segment names are accepted. The browser uses hls.js with native HLS as a fallback. Pause suspends FFmpeg; seeking restarts it at the requested position.

## Consequences

The path adds temporary storage and a JavaScript dependency. FFmpeg reopens the original by path after validation, leaving a race that the process API cannot make atomic; read-only mounts prevent writes by Bolognesa, not external changes. Synthetic tests validate output codecs, not server capacity or device playback. See [FFmpeg's HLS muxer](https://ffmpeg.org/ffmpeg-formats.html) and [hls.js](https://github.com/video-dev/hls.js).

# Video compatibility

Bolognesa checks the browser's reported support for each selected file before loading media. A format being eligible below does not guarantee playback on every device. Container, exact codec/profile/level, pixel format, resolution, audio and the browser's available playback APIs all matter.

## Delivery and format limits

| Delivery | Eligible input and behavior |
| --- | --- |
| Original file | MP4/MOV, WebM or Matroska with exact recognized H.264/HEVC and optional AAC-LC identifiers, unambiguous tracks, and a positive browser test. Matroska is not automatically playable on iPhone. Other originals can be tried explicitly without a compatibility promise. |
| HLS remux | Copy H.264 Constrained Baseline or Main, level 4.1 or lower, 8-bit yuv420p, up to 1920×1080 at 30 fps. Audio is absent or AAC-LC, mono/stereo at 32, 44.1 or 48 kHz. |
| HLS audio conversion | Preserve eligible H.264 video and convert selected audio to AAC-LC stereo, 48 kHz, 128 kbps. This can handle audio that cannot be copied, such as MP3. |
| HLS video/full conversion | Requires known SDR source facts. Encode H.264 Constrained Baseline level 4.1, 8-bit yuv420p, up to 1920×1080 and 30 fps, with an 8 Mbps video maximum; copy eligible AAC or convert audio as needed. |
| HEVC | Original delivery needs a positive exact browser test. Copying HEVC into HLS is unavailable; known-SDR sources can be encoded to H.264 under the video-conversion limits above. |
| HDR conversion | Unavailable. No HDR/Dolby Vision conversion or tone mapping. |

Copied video with a known average bitrate above 8 Mbps is excluded. Missing average bitrates remain unknown. Video copying may preserve absent color declarations; explicitly unsupported color/HDR declarations exclude it. Video encoding requires known SDR color facts. There is no subtitle burn-in or track selector; HLS uses the first non-cover video and first audio stream.

The least expensive positively supported delivery wins. HLS.js requires exact MediaSource codec support; native HLS requires a recognized playlist type and positive exact stream-codec support. For a generic playlist MIME, WebKit's `maybe` recognizes the transport; exact stream codecs must still return `probably`. Uncertain codec support does not silently become supported.

One shared conversion/remux session is available. Preparation, storage, authorization and cleanup limits still apply. Browser predictions do not prove actual decoding or network throughput.

## Device evidence

| Browser/device | Actual evidence | Status / limit |
| --- | --- | --- |
| Desktop Chrome 156.0.8078.81 | Synthetic source-derived FFmpeg/HLS and production player checks, including Main 3.1/720p25 and Main 4.1/1080p30 with audio conversion | Verified for those fixtures and the documented desktop test matrix; not every file. |
| Local Playwright WebKit build 2140 | Generic HLS MIME returns `maybe`; exact Main 4.0/AAC-LC MP4 codecs return `probably` | Reproduces the pre-correction rejection; the corrected probe accepts native HLS and a synthetic Main 4.1/1080p30 + AAC fixture advances through native HLS without a media error. This macOS test engine does not certify iPhone playback. |

A mobile-sized desktop viewport is not an iPhone test. Keep physical-device results separate from synthetic fixtures and capability predictions. See [issue #10](https://github.com/avillen/bolognesa/issues/10) for ongoing acceptance evidence and [the testing convention](conventions/testing.md) for runnable checks.

## When playback stops before starting

An inspection refresh helps when stored decoding facts are missing or stale. It cannot invent color declarations absent from the original file, and is unnecessary when a correction only changes capability handling. The technical-data warning can also appear after all eligible candidates fail browser negotiation; it is not proof that reanalysis will help.

Record the exact warning, device, OS/browser versions and whether playback ever started when reporting a failure. Share a selected episode/movie URL privately; do not publish media paths or library inventories. The explicit original action is an attempt without a compatibility guarantee.

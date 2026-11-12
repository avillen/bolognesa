# Playback verification

Procedures for controlled browser and FFmpeg checks. Follow the [testing conventions](conventions/testing.md) for test design and the [native setup](../CONTRIBUTING.md#native-development) for local execution. Docker-based screenshot checks are explicit, optional workflows.

## Browser player verification

`npm test` (or `node --test assets/test/*.mjs`) checks browser hook event contracts and the full-file
timeline adapter. Run it alongside `mix precommit`, which covers Elixir checks and ExUnit
but does not invoke the Node suite. The screenshots workflow’s `video` job runs `npm test`
and synthetic video checks in CI. `npm run test-video-player -- tmp/videojs-fixtures` runs the production
Video.js hook in Playwright against synthetic MP4/HLS fixtures and captures LiveView events
at the browser boundary. It checks controls, global seeks, pause/resume, fullscreen session
replacement, drag commit behavior, paused seeks, and Spanish labels. This does not replace
an end-to-end check with FFmpeg sessions and representative media on target devices.

`bash scripts/screenshots/run-readme-screenshots.sh --verify-music-host` verifies that the
authenticated root layout renders the persistent player host and public pages do not.
`bash scripts/screenshots/run-readme-screenshots.sh --verify-persistent-music` uses
synthetic media and an isolated database to verify navigation continuity, queue progression
outside Music, socket reconnection, unavailable-track retry, logout cleanup, keyboard
expansion, and a 375px browser viewport. The viewport check runs in desktop Chromium and
does not establish compatibility with real mobile browsers or devices.

`npm run measure-hls -- tmp/videojs-fixtures` measures the production hook against
a controlled synthetic HTTP producer, with two-minute phases and bootstrap reported
separately. Accounting and playlist-generation tests run with the Node suite. See the
[monitoring procedure](../deploy/compose/monitoring.md#measure-hls-request-behavior)
for report interpretation, a short smoke check, and the separate target-server baseline.
This tool observes paused polling; it does not require that polling to remain present.

`bash scripts/screenshots/run-readme-screenshots.sh --verify-fullscreen` checks stable fullscreen through real LiveView episode navigation and an unclassified native error. Its pinned-browser WebM demo deliberately uses the explicit original action; unknown metadata on the next episode may remain terminal. It does not establish negotiated conversion or ready playback after continuation. Use the negotiated-delivery matrix below for actual FFmpeg delivery and natural EOF across parts/episodes. The workflow uses its isolated Docker browser/database dependencies and does not update README captures.

Generate disposable fixtures with FFmpeg, then use an installed Chrome with H.264 support:

```sh
mkdir -p tmp/videojs-fixtures
ffmpeg -y -f lavfi -i color=c=black:size=320x180:rate=24 -t 20 -an \
  -c:v libx264 -preset ultrafast -g 24 -pix_fmt yuv420p -movflags +faststart \
  tmp/videojs-fixtures/sample.mp4
ffmpeg -y -i tmp/videojs-fixtures/sample.mp4 -c copy -hls_time 2 -hls_list_size 0 \
  -hls_segment_filename 'tmp/videojs-fixtures/segment%03d.ts' tmp/videojs-fixtures/index.m3u8
BOLOGNESA_TEST_BROWSER_CHANNEL=chrome npm run test-video-player -- tmp/videojs-fixtures
```

An existing Playwright server can be selected with `BOLOGNESA_SCREENSHOT_BROWSER_WS`.
Its browser must support H.264. The pinned screenshot Chromium verifies synthetic WebM
playback and Video.js controls through the actual LiveView; it does not establish H.264
or HLS decoding support.

### Negotiated delivery acceptance

`scripts/playback/verify-negotiated-output.exs` generates disposable synthetic sources and executes source-derived FFmpeg plans. Run `mix run --no-start scripts/playback/verify-negotiated-output.exs tmp/negotiation-check`. It checks actual profile/pixel format/AVC configuration, independent stream actions and copied payload equivalence, reporting any leading AAC priming-packet trim. Add `--anamorphic` after the directory for the real-output display-aspect regression.

Add `--main-copy` for Main 3.1/720p25 and Main 4.1/1080p30 sources with MP3 audio and absent color declarations; this verifies AAC output, exact retained AVC configuration and copied video bytes.

For a source-derived browser check, place an AAC/MP4 copy of the synthetic source at `sample.mp4` inside its generated output directory, then pass that directory and its `probe.json` to `npm run test-video-player -- <output-directory> <output-directory>/probe.json`. The optional probe checks exact output support before opening media and decodes the generated HLS through the production hook. Use an installed H.264-capable Chrome as above. These checks do not establish physical-device support. The matched remux/full-conversion timing from the default matrix is a local synthetic observation, not target-server capacity.

For the real LiveView path, configure a disposable native demo following [CONTRIBUTING](../CONTRIBUTING.md#local-demo-data). Run `scripts/playback/seed-negotiation-check.exs` through `mix run`, passing the generated fixture directory and that demo's `sample-ids.json`, with the same `BOLOGNESA_DB_NAME` and `BOLOGNESA_LIBRARY_ROOTS` as the demo server. The seeder refuses ordinary databases and adds only its synthetic fixture rows; it does not reset an installation. Start the matching native server, then run:

```sh
BOLOGNESA_TEST_BROWSER_CHANNEL=chrome node scripts/playback/verify-negotiated-liveview.mjs \
  http://localhost:4010 tmp/negotiation-check/browser-ids.json tmp/demo-credentials.json
```

Use the actual isolated server URL. The local credentials JSON contains `email` and `password` for that disposable account; never commit it or reuse a personal password. Stabilize assets before running and avoid source edits/hot reload during the check. The script exercises actual generated media, controls, seeks, fullscreen feedback, one decode recovery, a real aborted original download and natural EOF through parts/episodes. It labels controlled negative original capability results and injected native error codes explicitly; these do not prove a natural decoder failure or universal original-container support. Native HLS and physical Chrome on iPhone require separate device checks.

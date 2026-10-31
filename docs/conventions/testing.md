# Testing conventions

Tests focus on observable behavior and protect contracts while allowing implementation changes. Keep the effort proportional to the change.

## Workflow

1. Read existing tests for the behavior being changed.
2. For functional changes, add or update a relevant scenario and verify that it fails for the expected reason.
3. Implement the smallest change that makes it pass, then refactor while preserving verified behavior.
4. Run checks appropriate to the change and `mix precommit` for meaningful implementation work.

Documentation-only and formatting changes do not need artificial red/green tests. Refactors rely on existing coverage; address relevant gaps when found.

## Test design

- Update an existing test when its behavior changes. Add a test for a distinct scenario or uncovered regression.
- Keep useful regression coverage. Do not weaken expectations just to make a test pass.
- Name tests after the rule or result they verify. Keep fixtures and helpers local and clear.
- Assert returned data, domain rules, authorization, persisted changes, and visible interface behavior. Avoid private functions, socket internals, and exact call order unless they are part of the contract.
- Choose the lowest layer that protects the behavior. Do not duplicate every scenario across every layer.

| Area | Focus |
| --- | --- |
| Domain | Invariants, transitions, and errors without a database |
| Application | Public use cases and ports; use doubles to isolate external effects |
| Persistence and infrastructure | PostgreSQL constraints, mappers, atomic request/job insertion, and controlled external resources |
| LiveView | LiveViewTest interactions, stable selectors, visible results, and navigation |
| Reducers, view models, and forms | Direct tests when a meaningful transition or validation warrants them |
| Jobs and events | Recovery, duplicates, stale results, durable effects, and deterministic synchronization |

Keep doubles at external boundaries. Integration tests verify guarantees doubles cannot provide, such as transaction atomicity and database constraints. Normal tests do not depend on public providers or real NAS/TV hardware. Do not change global configuration from concurrent tests.

## Verification and processes

Run focused tests during development and broaden checks when risk or project requirements call for it. Record actual commands and distinguish automated checks from manual device verification. Unit tests do not establish hardware compatibility.

- Use `Bolognesa.DataCase` for database tests. Give collaborating processes sandbox allowances; shared mode requires `async: false`. A shared sandbox connection does not prove behavior between independent transactions.
- Use distinct fixture values for unique constraints. For race/locking tests, use independent connections and deterministic coordination; keep the configured minimum pool size of five. Do not hide pool exhaustion with longer timeouts.
- Start processes with `start_supervised!/1` so they are cleaned up between tests.
- Synchronize on messages, monitors, or explicit acknowledgements instead of sleeping or polling `Process.alive?/1`. A synchronous call such as `:sys.get_state/1` can flush earlier messages sent by the same sender; it does not prove completion of work delegated to another process.

See the [SQL Sandbox ownership guide](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) for allowances, shared mode, and process cleanup.

## Browser player verification

`node --test assets/test/*.mjs` checks browser hook event contracts and the full-file
timeline adapter. `npm run test-video-player -- tmp/videojs-fixtures` runs the production
Video.js hook in Playwright against synthetic MP4/HLS fixtures and captures LiveView events
at the browser boundary. It checks controls, global seeks, pause/resume, fullscreen session
replacement, drag commit behavior, paused seeks, and Spanish labels. This does not replace
an end-to-end check with FFmpeg sessions and representative media on target devices.

`npm run measure-hls -- tmp/videojs-fixtures` measures the production hook against
a controlled synthetic HTTP producer, with two-minute phases and bootstrap reported
separately. Accounting and playlist-generation tests run with the Node suite. See the
[monitoring procedure](../../deploy/compose/monitoring.md#measure-hls-request-behavior)
for report interpretation, a short smoke check, and the separate target-server baseline.
This tool observes paused polling; it does not require that polling to remain present.

`bash scripts/screenshots/run-readme-screenshots.sh --verify-fullscreen` seeds two
synthetic episodes in an isolated database and checks automatic continuation, the
next-episode link, and a browser-error conversion attempt through the real LiveView.
It asserts fullscreen, video identity, and continuous connection of the player's
ancestors. The hook-only browser fixture does not exercise DOM changes made by LiveView.
This check uses the screenshot workflow's Docker and browser dependencies and does not
update README captures. When FFmpeg is unavailable, the conversion attempt verifies
fullscreen through the visible preparation failure instead of a ready HLS session.

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

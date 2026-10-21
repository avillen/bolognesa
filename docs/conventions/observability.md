# Observability conventions

Bolognesa currently uses structured `Logger` messages with stable text and metadata fields. It does not add a separate metrics or tracing platform at this stage; Phoenix's existing instrumentation may remain.

```elixir
Logger.info("Library scan completed",
  library_id: library_id,
  scan_id: scan_id,
  files_discovered: count,
  duration_ms: duration_ms
)
```

- Keep message text stable. Put IDs, counters, durations, and bounded reason codes in metadata.
- Configure the formatter to show approved fields; adding metadata alone does not guarantee that it appears in output.
- Log meaningful job starts, outcomes, retries, and failures. Avoid logging every trivial operation or playback update.
- Use `debug` for diagnostic detail, `info` for normal milestones, `warning` for degradation or retries, and `error` for terminal or unexpected failures.
- Pass context explicitly to asynchronous work; process metadata is not automatically inherited.
- Log a failure at the layer that understands its operational result. Avoid duplicate logs as errors propagate.
- Never dump structs, external responses, parameters, or exceptions without checking for sensitive data. Exclude passwords, tokens, cookies, credentials, unnecessary full paths, and private media listings.
- The domain does not depend on `Logger`; the application and adapters log at their boundaries.

Logs do not replace persisted job state, an outbox, or user-facing feedback. Test log contents only when they are part of an operational or confidentiality contract.

Movie searches use the `query` parameter, filtered by Phoenix along with passwords and tokens. Ecto queries and writes containing private titles, candidates, or paths use `log: false`. Operational diagnostics use internal IDs and bounded reason codes.

## Telemetry

Use Telemetry for new operational instrumentation that needs diagnostic logs or metrics.
Existing direct Logger calls can remain until their behavior is revised. Telemetry events
are observations, not domain events, durable delivery, or a way to trigger business work.
Emit them at application, infrastructure, or web boundaries; the domain remains independent.

- Name application events `[:bolognesa, context, resource, outcome]` using a fixed set of
  atoms. Never construct event names or atoms from request data.
- Keep numeric measurements separate from metadata: `count: 1` for occurrences,
  `duration_ms` for elapsed milliseconds, and explicitly named units for positions and
  offsets. Measure elapsed time with a monotonic clock. Standard `:telemetry.span/3`
  events use `:start`, `:stop`, and `:exception` and native time units; convert those units
  in the reporter. Long-lived playback lifecycle events are independent observations,
  not synchronous spans.
- Document each event's owner, measurements, metadata, and delivery limits when adding it.
  Treat event names, field meanings, and bounded reason codes as observable contracts.
- Keep diagnostic identifiers in logs. Metric tags use small, fixed sets such as profile,
  outcome, and reason; never tag metrics by session, tab, user, file, path, or URL.
- The supervised `Bolognesa.Infrastructure.Observability` subscriber writes one structured
  operational log per supported event. Do not also log the same observation at its emitter.
  Its handler uses an explicit metadata allowlist; approve formatter fields as well.
- Register stable handler IDs once during application startup. Detach/reinstall safely on
  subscriber restart, including recovery after an untrappable exit. Handlers execute
  synchronously in the emitter: no database queries, filesystem/network calls, blocking
  work, or business effects. Keep handlers small and defensive; a failed handler is
  detached by Telemetry and observations can then be lost.
- Sanitize at the emitter before passing metadata to any subscriber. Browser diagnostics
  are untrusted: validate IDs, enums, numeric bounds, current file/session correlation,
  and event volume. Never emit raw event payloads, exception terms, FFmpeg output, media
  names, credentials, cookies, private paths, or complete URLs.
- Telemetry does not retain events. Docker's rotated application logs provide the current
  diagnostic history; LiveDashboard metrics show observations collected while connected,
  not a durable historical store. No additional metrics backend is required.

### Playback events

Playback infrastructure owns the session events; shared playback LiveView support owns
page/browser observations; the HLS controller owns failed delivery observations. All events
below have prefix `[:bolognesa, :playback]` and measurement `count: 1`.

| Suffix | Additional measurements | Metadata |
| --- | --- | --- |
| `[:session, :started]` | None | `session_id`, `file_id`, `profile`, `offset_ms` |
| `[:session, :closed]` | `duration_ms` | `session_id`, `file_id`, `profile`, `reason`; normalized `termination_reason` for owner exits |
| `[:session, :exited]` | `exit_status` | `session_id`, `file_id`, `profile`, `reason` (`finished` or `failed`) |
| `[:liveview, :terminated]` | None | `session_id`, `file_id`, normalized `termination_reason` |
| `[:hls, :failed]` | None | Valid UUID `session_id` when supplied, `resource_type`, `failure_stage`, `reason`, HTTP `status` |
| `[:browser, :diagnostic]` | None | `tab_id`, current `session_id`/`file_id`, `diagnostic`, `position_ms`, `paused`, `visibility`, `sequence`, `client_time_ms`, numeric `media_error` |

Session close reasons distinguish `version_selected`, `seek`, `ended`, `client_error`,
`preparation_timeout`, `source_invalidated`, `liveview_terminated`, `owner_terminated`,
`session_replaced`, `logout`, `idle_timeout`, `storage_limit`, `ffmpeg_failed`,
`process_missing`, `shutdown`, and explicit `operator_stop`. A source-invalidated close
identifies the cleanup action; the associated HLS failure records its validation reason.
Normal lifecycle logs use info, HLS/browser errors use warning, and unsuccessful FFmpeg
exits use error. Process exit details are reduced to `normal`, `closed`, `shutdown`, or
`abnormal`; these codes do not prove why a network connection was lost.

Browser observations cover mount, disconnect/reconnect, visibility changes, and media
errors, including fatal HLS errors before session cleanup. A random tab UUID is retained in session storage when available; it is only a
correlation hint, never authorization. Positions include the HLS file offset. The client
buffers at most eight observations during a hook disconnect and flushes them on reconnect.
The server accepts at most 120 valid observations per LiveView lifetime and drops stale or
invalid file/session observations. Client times are untrusted wall-clock hints; sequence
numbers order observations within one hook instance, not across reloads. Browser termination,
a full reload, hook destruction, or prolonged suspension can lose pending observations.
Neither LiveView termination callbacks nor final browser signals are guaranteed on abrupt
process/device termination. Diagnose with both server and browser evidence; missing signals
are not proof that an event did not happen.

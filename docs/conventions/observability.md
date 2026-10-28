# Observability conventions

Use application Telemetry events and the supervised structured Logger subscriber. Phoenix,
Ecto, and Oban retain their instrumentation. External monitoring is optional; follow the
[monitoring guide](../../deploy/compose/monitoring.md) to configure it.

## Logs and privacy

- Log meaningful starts, outcomes, retries, and failures at the boundary that understands
  their operational result. Avoid duplicate logs, idle polls, successful chunks, and per-frame updates.
- Keep messages stable; put approved IDs, counters, durations, and bounded reason codes in metadata.
  Configure formatter fields explicitly. Pass correlation data to async work instead of relying
  on inherited process metadata.
- Use `debug` for diagnostic detail or stale work, `info` for normal milestones, `warning`
  for degradation or retries, and `error` for terminal or unexpected failures.
- Never dump parameters, structs, provider responses, exception terms, or media tool output.
  Exclude credentials, cookies, private titles, paths, and media inventories. Filter sensitive
  Phoenix parameters (including search `query`) and use `log: false` for Ecto operations that
  contain private data; review new entry points and queries for leaks.
- Keep the domain independent of Logger and Telemetry. Logs do not replace persisted job
  state, durable delivery, or user-facing feedback.

## Events and delivery

Use `Bolognesa.Infrastructure.Observability.Events` for context observations and the existing
validated Playback emitters for playback. The shared subscriber produces the operational log;
do not log the same observation at its emitter.

```elixir
Events.emit(:libraries, :scan, :completed,
  %{library_id: library_id, scan_id: scan_id, job_id: job_id, attempt: attempt},
  %{files_discovered: count, duration_ms: duration_ms}
)
```

- Use fixed event names such as `[:bolognesa, context, resource, outcome]`; never construct
  atoms from input. Update the event allowlists and relevant tests together.
- Separate numeric measurements from metadata. Use `count: 1` for occurrences and explicit
  units such as `duration_ms`; measure elapsed time with a monotonic clock. Standard
  `:telemetry.span/3` durations use native units and need conversion in the reporter.
- Report committed changes only after the owning transaction succeeds. Preserve committed
  partial recovery results; a failed attempt does not prove that a retry or terminal write succeeded.
- Sanitize before emission so every subscriber sees safe data. Validate browser IDs, enums,
  numeric bounds, current file/session correlation, and volume; client diagnostics are untrusted.
- Handlers run synchronously in the emitter. Keep them small, defensive, and free of blocking
  I/O or business effects. Register stable handler IDs at startup and handle subscriber restarts.
  Telemetry detaches failing handlers and does not retain or replay observations.
- Treat missing observations as missing evidence. Abrupt termination, browser suspension,
  disconnects, detached handlers, and log rotation can lose data.

## Metrics and optional export

- Use small fixed label sets for outcomes, strategies, and reasons. Keep user, file, session,
  tab, path, query, URL, and raw exception data out of labels; use route templates for HTTP metrics.
- Keep external export opt-in and credential-protected. Exported operational counters and
  histograms remain unlabelled; richer bounded local labels do not automatically belong in export.
- Update generated dashboards when metric contracts change. Distinguish missing data from zero
  and interpret percentiles and scrape-based counts as estimates, especially with few samples.
- Monitoring failures must not break business workflows. Keep collectors and their privileges
  separate from the application; follow the [monitoring guide](../../deploy/compose/monitoring.md#optional-docker-resources-on-native-linux) for optional Docker collection.

These rules follow [Telemetry handler semantics](https://hexdocs.pm/telemetry/telemetry.html#attach/4).

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

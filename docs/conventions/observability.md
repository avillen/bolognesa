# Observability conventions

Bolognesa uses application Telemetry events with a supervised structured `Logger`
subscriber. Phoenix, Ecto, and Oban retain their existing instrumentation. There is no
required external metrics or tracing platform. Optional PromEx collection and an Alloy
Compose override can forward metrics to Grafana Cloud; both are disabled in the
normal installation. See the [monitoring guide](../../deploy/compose/monitoring.md).

```elixir
Events.emit(:libraries, :scan, :completed,
  %{library_id: library_id, scan_id: scan_id, job_id: job_id, attempt: attempt},
  %{files_discovered: count, duration_ms: duration_ms}
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
The context rollout uses `Bolognesa.Infrastructure.Observability.Events` to validate
fixed events and sanitize measurements and metadata before calling Telemetry. Existing
Playback emitters preserve their separately validated contracts below. Telemetry events
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
- Keep diagnostic identifiers in logs. Metric tags use small, fixed sets such as transcode strategy,
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
  local diagnostic history; LiveDashboard metrics show observations collected while
  connected, not a durable historical store. No external observability backend is
  required. An operator can explicitly opt into PromEx/Alloy metrics or application-only
  Alloy/Loki logs. Both are optional deployment features; see the
  [monitoring guide](../../deploy/compose/monitoring.md).

### Cross-context audit and ownership

The audit includes application use cases, workers, recovery, provider/probe adapters,
notification transports, delivery controllers, and UI callers. No direct operational
Logger calls remain outside the shared subscriber. Its two logging paths intentionally
preserve established Playback messages and report new observations with the stable message
`Bolognesa operational observation` and explicit `context`, `resource`, and `outcome`.

| Area | Observation owner and coverage | Deliberately quiet boundaries |
| --- | --- | --- |
| Accounts | `InstallAdmin`, `StartSession`, `EndSession`, and `UpdateLocale` observe committed mutations and persistence failures. `ResolveSession` observes persistence failure only. Logout distinguishes an actual deleted row from an absent session internally. | Input validation, authorization, setup already closed, missing/revoked sessions, no-op logout, and successful session/admin reads. Invalid credentials have a separate debug observation. |
| Libraries scans | `StartScan` observes accepted durable requests; `DiscoverFiles` observes admitted attempts and committed outcomes before return normalization. `ScanWorker` owns unexpected escaped execution failures. | Inventory batches, terminal replay except debug stale observation, source-registration validation, and ordinary library/status reads. |
| Libraries inspection | `InspectMediaFile` observes admission, probe results, persisted completion/terminal failure, retryable execution, and stale suppression. Its optional typed probe diagnostic callback preserves the safe `file_access`/`ffprobe` stage without a second adapter log. `InspectionWorker` owns escaped exceptions. | Probe internals and duplicate/stale work beyond its debug observation. Private FFprobe output is never included. |
| Libraries recovery/notifications | Reconciliation use cases observe committed changed-library counts, including changes preceding partial failure. Reconcilers own only escaped failures. `LibraryStatusNotifications` owns degraded PubSub delivery. | Idle recovery, individual status hints on successful delivery, and neutral PubSub transport. Changed-library counts are not recovered-item counts. |
| Movies | `IdentifyMovieFile` observes admitted attempts, committed matched/review/no-match results, stale work, provider-stage failures, and retries before normalization. Correction/retry use cases observe confirmed writes and operational failures. `ReconcileIdentificationJobs` observes committed recovery counts; worker/reconciler catches own escaped failures. | Catalog/detail reads, expected authorization/input refusals, and provider transport. |
| Series | Equivalent Series-owned use cases and job boundaries, with Series matching/review reasons and ordered-selection semantics. | Same read/transport exclusions as Movies; Series does not share business instrumentation with Movies. |
| Music | `RefreshWorker` observes attempt admission and confirmed exhaustion writes; `RefreshTrack` observes actual imports, stale observations, and operational failures with explicit job correlation. `RetryImport` observes a newly committed retry. `ReconcileImports` observes committed recovery counts and partial failures; reconciler catches escaped failures. | Unchanged retries, forbidden/absent retry targets, ordinary browsing, and transaction-aware import handoff before its enclosing transaction commits. |
| Playback | Existing session/browser/HLS owners remain unchanged. Direct controllers attach validated resource references; shared `MediaDelivery` owns selection, source/range/read/send failures for audio and video. | Successful byte ranges/chunks and per-request authentication refusals already covered by framework instrumentation. |
| Shared/web | Standalone Movies/Series candidate search owns its own provider-failure observation. Identification/correction instead includes the provider stage in its outcome. UI retains user feedback. Phoenix/Ecto/Oban instrumentation remains in place. | Neutral TMDb HTTP transport, generic PubSub transport, and repeated UI logging of a backend outcome. No event is emitted for every function or catalog read. |

### Operational event catalog

All names have prefix `[:bolognesa, context]`; combine each resource with one of the
listed outcomes to obtain the exact registered four-atom event. Names and field meanings
are fixed contracts, not derived from input. Every observation has measurement `count: 1`.
All listed fields are optional when unavailable at that boundary.

| Context | Resource | Outcomes | Metadata emitted by the owner | Additional measurements |
| --- | --- | --- | --- | --- |
| `accounts` | `setup` | `completed`, `failed` | Successful `user_id`; failure `reason` | None |
| `accounts` | `session` | `completed`, `failed`, `rejected` | `operation` (`start`, `revoke`, `resolve`), `user_id` on creation; `result: deleted` on actual revocation; failure `reason`, `failure_stage: session_lookup` on failed resolution | None |
| `accounts` | `preference` | `completed`, `failed` | `user_id`, `operation: locale`, failure `reason` | None |
| `libraries` | `scan` | `requested`, `started`, `completed`, `failed`, `retryable`, `stale`, `rejected` | `library_id`, `scan_id`, `job_id`, `attempt`; bounded `reason`; `operation: request` for failed enqueue | Attempt `duration_ms`; `files_discovered` only for committed completion |
| `libraries` | `inspection` | `started`, `completed`, `failed`, `retryable`, `stale` | `file_id`, `job_id`, `attempt`; `library_id`/`revision` after admission; `reason`, safe `failure_stage` | `duration_ms` on outcomes |
| `libraries` | `reconciliation` | `recovered`, `retryable`, `failed` | `operation` (`scan` or `inspection`), `reason` on failure | `changed_library_count`, `duration_ms` except escaped process failures |
| `libraries` | `notification` | `degraded` | `library_id`, `reason: notification_unavailable` | None |
| `movies`, `series` | `identification` | `requested`, `started`, `completed`, `retryable`, `failed`, `stale`, `rejected` | `file_id`, `job_id`, `attempt`, `revision` when admitted; `user_id`/`operation: retry` for explicit retry; `result`, `reason`, `failure_stage` as applicable | `duration_ms` for use-case execution |
| `movies`, `series` | `correction` | `completed`, `failed`, `stale` | `user_id`, `file_id`, successful `revision`, failure `reason`/`failure_stage` | `duration_ms` |
| `movies`, `series` | `provider` | `failed` | `user_id`, `operation: search`, `failure_stage: search`, safe provider `reason`; standalone candidate search only | None |
| `movies`, `series` | `reconciliation` | `recovered`, `failed` | Failure `reason`/`failure_stage` when available | `recovered_count` (also retained on partial failure), `duration_ms` except escaped failures |
| `music` | `import` | `requested`, `started`, `completed`, `stale`, `retryable`, `failed` | `file_id`, `revision`, `job_id`, `attempt`; successful `library_id`/`result: imported`; retry `user_id`/`operation: retry`; `reason`, `failure_stage` | `duration_ms` for use-case execution |
| `music` | `reconciliation` | `recovered`, `retryable`, `failed` | `reason`, `failure_stage: recovery` on failure | `recovered_count`, `changed_library_count`, `duration_ms` except escaped failures |
| `playback` | `delivery` | `failed` | Valid `file_id`, `resource_type` (`movie`, `episode`, `music`), `failure_stage`, `reason`, actual HTTP `status` | None |

`Events` validates a fixed per-resource field allowlist. Diagnostic IDs and attempts are
positive integers bounded by 9,223,372,036,854,775,807; measurements are nonnegative integers
with the same upper bound. HTTP statuses range from 100 to 599. Unknown names, metadata
keys, enum values, and invalid measurements are dropped; `count` is always set to one.
The subscriber validates again defensively. Its operational log path overrides inherited
formatter fields, so request/process metadata cannot bypass event validation. Authentication
tokens and inspection/request tokens are never correlation identifiers.

The bounded reason vocabulary covers existing scan/inspection, identification policy,
provider, account, and delivery outcomes:

- Storage/execution: `unavailable`, `storage_unavailable`, `unexpected_failure`,
  `attempts_exhausted`, `timeout`, `tool_unavailable`, `invalid_job`.
- Source/probe: `source_inaccessible`, `source_outside_roots`, `source_changed`,
  `entry_unreadable`, `unsafe_entry`, `unreadable`, `unsupported`, `invalid_output`, `missing`.
- Identification/provider: `unusable_name`, `not_configured`, `rate_limited`,
  `provider_unavailable`, `unauthorized`, `invalid_response`, `not_found`,
  `wrong_content_type`, `ambiguous_name`, `invalid_episode_numbers`, `too_many_episodes`,
  `incomplete_episodes`, `ambiguous_series`, `no_match`, `invalid_choice`, `manual_locked`.
- Account/refusal/replay: `invalid_credentials`, `unauthenticated`, `forbidden`,
  `setup_closed`, `invalid_locale`, `scan_in_progress`, `invalid_input`, `terminal`,
  `stale_observation`, `stale_attempt`.
- Delivery/notification: `notification_unavailable`, `invalid_range`, `unsatisfiable`,
  `read_failed`, `client_closed`, `send_failed`, `invalid_reference`, `empty_read`.

Stages emitted by this rollout are `admission`, `persistence`, `search`, `details`, `season`,
`execution`, `recovery`, `file_access`, `ffprobe`, `import`, `exhaustion`, `retry`,
`session_lookup`, `selection`, `source_validation`, `range`, `read`, and `chunk`.
Identification completion results are `matched`, `review`, or `no_match`. A correction
refused because the source changed is a stale outcome, not a confirmed correction.

Normal milestones use info; `stale`/`rejected` use debug; `retryable`/`degraded` and failed
standalone provider/direct-delivery observations use warning; other `failed` observations
use error. Execution failure does not assert a persisted terminal state. A `retryable`
observation reports the failed attempt, not confirmation that Oban has scheduled a retry.
Music may additionally report `failed` at `exhaustion` after the separate terminal-state
transaction succeeds; this describes a different confirmed boundary. If that write fails
or becomes stale, its observation says so instead.

### Correlation, commit truth, metrics, and delivery limits

Workers explicitly pass persisted `job_id`, file/scan IDs, and `attempt` into the owning
use case. Attempts within one job share its ID; replacement jobs have new IDs. These
identifiers appear only in diagnostic logs, never metric tags. No reliance is placed on
inherited process metadata. Ordinary request/session lookups do not emit success events.

Observe committed writes only after the owning transaction returns successfully. Inner
inventory/import request handoffs emit no commit success; the enclosing transaction can
still roll back. Stale checks remain visible before public results normalize to `:ok`.
Recovery counts actual committed transitions and retains partial progress; stale candidates
do not count as recovered. Libraries counts distinct changed libraries because its existing
contract does not supply recovered-item counts. Idle reconciliation emits nothing.

Existing Playback metrics retain their names and meanings. New supported operational
events expose `.count` sums and `.duration_ms` summaries through `BolognesaWeb.Telemetry`.
Summaries receive samples only when the emitter measures a duration; lifecycle starts and
outcomes are independent observations, not synthetic synchronous spans. Duration units
are milliseconds from a monotonic clock. Counter tags are bounded `reason`, `operation`,
`result`, `failure_stage`, and `resource_type`; duration tags are `reason` and `operation`.

Events are synchronous, best effort, and not replayed. One supported observation produces
one subscriber log; repeated attempts can produce repeated observations. Handlers perform
no database/network/filesystem calls or business effects. Stable registration replaces a
leftover handler on ordinary restart or after an untrappable exit. Abrupt death, detached
handlers, and log rotation can lose evidence. Workflow activity and bounded recovery
batches bound emission; successful delivery chunks and idle polls do not create log traffic.
Direct streaming failures after headers retain the original HTTP status and record the
failure stage instead of claiming a new response status. They do not establish why a
connection was lost. A known closed connection is `client_closed`, a known timeout is
`timeout`, and an otherwise unclassified send failure is `send_failed`; raw transport
errors are discarded. Existing browser limits remain as documented below.

### Playback events

Playback infrastructure owns the session events; shared playback LiveView support owns
page/browser observations; the HLS controller owns failed delivery observations. All events
below have prefix `[:bolognesa, :playback]` and measurement `count: 1`.

| Suffix | Additional measurements | Metadata |
| --- | --- | --- |
| `[:session, :started]` | None | `session_id`, `file_id`, `strategy`, `offset_ms` |
| `[:session, :closed]` | `duration_ms` | `session_id`, `file_id`, `strategy`, `reason`; normalized `termination_reason` for owner exits |
| `[:session, :exited]` | `exit_status` | `session_id`, `file_id`, `strategy`, `reason` (`finished` or `failed`) |
| `[:liveview, :terminated]` | None | `session_id`, `file_id`, normalized `termination_reason` |
| `[:hls, :failed]` | None | Valid UUID `session_id` when supplied, `resource_type`, `failure_stage`, `reason`, HTTP `status` |
| `[:browser, :diagnostic]` | None | `tab_id`, `page_id`, `session_id`/`file_id`, `diagnostic`, `position_ms`, `paused`, `visibility`, `sequence`, `client_time_ms`, numeric `media_error`, `buffered_ms`, `stall_duration_ms`, `replayed`, `ready_state`, `network_state`, `online`, `navigation_type`, `ws_code`, `ws_clean` |

Session close reasons distinguish `version_selected`, `seek`, `ended`, `client_error`,
`preparation_timeout`, `source_invalidated`, `liveview_terminated`, `owner_terminated`,
`session_replaced`, `logout`, `idle_timeout`, `storage_limit`, `ffmpeg_failed`,
`process_missing`, `shutdown`, and explicit `operator_stop`. A source-invalidated close
identifies the cleanup action; the associated HLS failure records its validation reason.
Normal lifecycle logs use info, HLS/browser errors use warning, and unsuccessful FFmpeg
exits use error. Process exit details are reduced to `normal`, `closed`, `shutdown`, or
`abnormal`; these codes do not prove why a network connection was lost.

Browser observations cover mount, disconnect/reconnect, visibility changes, and media
errors, including fatal HLS errors before session cleanup. `waiting` records a buffer
wait while playback is requested; duplicate waits are coalesced until `playing` emits
`recovered`. `buffered_ms` measures contiguous media ahead of the current position;
`stall_duration_ms` measures the wait with the browser monotonic clock and is zero for
other observations. Both fields accept integers from zero to 2,147,483,647; absent fields
from older clients default to zero. Pausing, emptying/replacing the source, or destroying
the hook abandons an unfinished wait without a recovery event. These observations also
include startup and seek waits, not just interruptions after sustained playback.

A random tab UUID is retained in session storage when available; it is only a
correlation hint, never authorization. Positions include the HLS file offset. The client
buffers at most eight observations during a hook disconnect and flushes them on reconnect.
The server accepts at most 120 ordinary observations, 1,440 progress samples spaced at
least 25 seconds apart, and eight replayed observations per LiveView lifetime. Historical
progress uses the separate replay budget, so a recovered batch retains all its samples.
Ordinary observations require the current file/session; explicitly replayed observations
may reference an earlier valid session UUID for the current file. Client times are
untrusted wall-clock hints; sequence numbers order observations within one document,
not across reloads. Browser termination, a full reload, hook destruction, or prolonged
suspension can lose pending observations.
Neither LiveView termination callbacks nor final browser signals are guaranteed on abrupt
process/device termination. Diagnose with both server and browser evidence; missing signals
are not proof that an event did not happen.

The `controls` observation samples the packaged video skin once per hook, 350 ms after
its first `playing` event. The timer is cancelled on teardown and probe failures must
not affect playback. It uses the existing current-file/session validation and ordinary
observation budget. `controls_group_width`, `controls_slider_width`, `controls_track_width`,
`controls_slider_height` and `controls_track_height` are rounded CSS pixels, clamped to
0..100,000. `controls_labels` counts up to two nonempty time labels without sending text.
`controls_hidden` checks display, visibility and opacity on the time group and its shadow
ancestors; dimensions and flags are evidence of layout, not proof of visible pixels.
`css_container`, `css_layer`, `intl_units`, `intl_lists` and `unicode_properties` are capability probes;
`browser_major` is a parsed Chrome/Chromium major version capped at 999, or zero when
unrecognized. No raw user-agent string is transmitted. Missing elements, failed probes
and unavailable APIs can produce zero/false values, so these do not establish a specific
engine or root cause. These fields are log metadata only, never metric labels.

Additional browser diagnostic names are `pagehide`, `pageshow`, `online`, `offline`,
`socket_open`, `socket_closed`, `socket_error`, `destroyed`, `progress`, `restored`,
`restore_failed` and `autoplay_blocked`. Page IDs are random per document; tab IDs
survive reloads where storage is available. `navigation_type` is `navigate`, `reload`,
`back_forward` or `unknown`; media ready/network states use native bounded numeric enums.
WebSocket codes are zero when unavailable, otherwise integers from 1000 to 4999;
`ws_clean` records the browser's cleanliness flag. These observations do not include
raw reasons, URLs or exception text. A 30-second timer samples requested playback.
Up to eight unacknowledged observations survive in session storage for the same
viewer/content/file and can be replayed after a reload, with possible duplicates.
See [decision 0024](../decisions/0024-tab-playback-recovery.md) for recovery semantics.

## Optional Prometheus export

PromEx starts before Ecto/Oban only when explicitly enabled at runtime. Its bearer-protected
`/metrics` endpoint is disabled by default and does not use browser sessions. Exported
operational event counters and duration histograms intentionally have no metadata labels;
the richer bounded labels used by LiveDashboard remain local. HTTP export uses route
templates, removes request host labels and normalizes unknown methods. Client-controlled
channel/socket labels and client-supplied LiveView event labels are not collected. Keep existing diagnostic IDs,
private paths, queries and raw errors out of metric labels.

Alloy belongs to an optional deployment override and owns Cloud credentials and remote
write. The application never requires a Cloud account, uploads dashboards or sends metrics
over the network itself. Monitoring failures must not become business-workflow failures.
See [decision 0021](../decisions/0021-optional-prometheus-metrics.md) for the trade-offs.

### Project overview metrics

The operational Grafana dashboard is generated with
`scripts/build-operational-dashboard.py` from the registered event catalog. It groups
functionality by context and adds global Phoenix/LiveView, Ecto, Oban, BEAM and optional
Docker rows. Keep event coverage and framework selectors aligned with the code. Default
to a 24-hour view for low-volume use; show counts and mean/p50/p95 together. Missing
data must remain distinct from zero. Histogram percentiles are estimates, especially
with few samples, and cannot identify individual slow operations. Counts from `increase`
are scrape-based estimates, not a durable workflow ledger.

`LiveViewMetrics` adapts the pinned `PromEx.Plugins.PhoenixLiveView` definitions, replaces
all tag extraction with fixed view/context ownership, and adds handle_params/render
spans. Stop and exception durations retain native-to-millisecond conversion. Unknown
views are `global` / `other`; client event names, params, exception terms and URLs are
never metric labels. `EctoMetrics` preserves the bundled names and labels while refining
duration buckets for small queries and adds a repo/source-labelled query-error counter
only for `{:error, reason}` Ecto results; the reason itself is never exported. Operational buckets distinguish scans, other work,
and session lifetime. Mixed bucket layouts during an upgrade distort historical
quantiles; compare a post-upgrade window.

Existing operational counters/histograms stay unlabelled. `PlaybackMetrics` additionally
exports `bolognesa_playback_browser_observations_total` with a fixed `diagnostic` enum,
`bolognesa_playback_ffmpeg_exits_total` with `result` (`finished`, `failed`, `other`), and
`bolognesa_playback_session_closures_total` with the documented close `reason` vocabulary.
Unknown values become `other`; no session, file or tab identifiers are exported. The
existing browser validation and observation cap still apply.

HTTP attribution uses route templates; media delivery belongs to Playback. LiveView
attribution uses its screen's context. Ecto attribution uses the primary reported source,
not the caller; Oban uses worker ownership, not shared queue names. Shared tables,
transactions, connection-level timing, and unclassified queries remain visible globally.
Do not label unclassified Ecto commands as database errors or configured pool size as
connection occupancy.

Optional Docker resources use a dedicated, privileged Linux Alloy service. Keep this
permission separate from the app and ordinary metrics collector. Forward only selected
Compose-project services and allowlisted metrics/labels, including sanitized runtime IDs
needed to separate replicas/recreations. Drop raw cgroup paths and arbitrary container
labels. Verify scrape health and fresh expected-container samples separately. See
[decision 0023](../decisions/0023-project-overview-monitoring.md) and the
[monitoring guide](../../deploy/compose/monitoring.md#optional-docker-resources-on-native-linux).

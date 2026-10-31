# 0023. Project overview and optional Docker resource metrics

Status: Dashboard layout and publication superseded by [0026](0026-dashboard-as-code-publication.md). The exporter release is deployed on ARM64, and Docker CPU/memory/network forwarding is verified through the Grafana Cloud API. Representative resource accuracy and block-I/O data remain unverified.

## Context

The initial operational dashboard lists every event but makes individual functionality
hard to assess. Home use usually has one or two concurrent users, so short-window rates
and p95 alone provide little context. Framework metrics already exist, while LiveView
and Docker resource visibility need optional collection.

## Decision

- Generate one project overview with context-owned functionality and global framework,
  BEAM and Docker sections. Preserve the operational dashboard UID and manual import.
  Collapsed detail rows defer diagnostic query work; the initial range is 24 hours.
- Pair estimated observation volume with mean, p50 and p95. Keep terminal failures,
  retries and expected refusals distinct. Missing data is never coerced to healthy zero.
- Reuse the pinned PromEx LiveView plugin through an adapter that replaces tag extraction
  with fixed view/context ownership. Extend its missing parameter/render callbacks and
  exclude client event labels and exception text. Refine Ecto and operational histogram
  buckets without renaming their exported metrics. Count Ecto query errors separately
  using repo/source labels without error text.
- Preserve existing unlabelled operational metrics. Add three small Playback breakdowns
  with fixed diagnostic/result/closure-reason labels and an `other` fallback.
- Attribute HTTP by route, LiveView by screen, Ecto by primary source and Oban by worker.
  These are observations of their respective boundaries, not end-to-end caller tracing.
- Add `monitoring.docker.yaml` as a separate optional native-Linux Alloy/cAdvisor service.
  It owns the privileged host/socket mounts and a dedicated WAL. Filter forwarded data
  by Compose project/service, metric names and label allowlists. Keep scrape health and
  sanitized runtime container IDs; exclude arbitrary labels, raw cgroup paths and images.

## Consequences

LiveView histograms and finer buckets add series and require representative quota checks.
Historical ranges spanning a bucket-layout change can give misleading quantiles. Low
sample counts and scrape extrapolation remain visible limitations rather than exact
workflow counts or precise per-operation timings. Browser diagnostic caps remain in place.

The Docker override grants broad host access and is unsuitable as a default. Its exporter
can inspect unrelated containers locally, although forwarding is filtered. The pre-filter
8,000-sample guard can reject a scrape on a busy shared host. Runtime IDs add series churn.
Host-network traffic and storage-driver differences limit per-container resource attribution.
Collection failure does not block Bolognesa, and application deployment does not start the
collector. See the [operator guide](../../deploy/compose/monitoring.md).

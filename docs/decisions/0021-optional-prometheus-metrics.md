# 0021. Optional Prometheus metrics with PromEx and Alloy

Status: Implemented; ARM64 deployment and Grafana Cloud remote-write acceptance verified. Representative workload budgets remain unmeasured.

## Context

LiveDashboard and application logs provide local diagnostics but no durable metric
history. An operator wants Grafana Cloud while Bolognesa must remain practical to
self-host without any monitoring infrastructure or external account.

## Decision

- Add PromEx as an optional runtime collector, disabled by default. Start it before
  Ecto and Oban when enabled so their startup events are observed.
- Protect `/metrics` with an independent runtime bearer token. Disabled installations
  return 404. Collection does not depend on browser authentication or Cloud credentials.
- Export framework metrics and existing fixed application event counters/duration
  histograms. Operational events have no metadata labels. HTTP labels omit the host,
  use route templates and bound methods. Omit client-controlled channel/socket and
  LiveView event labels. Diagnostic details remain in logs and local LiveDashboard.
- Provide separate bridge/host Compose overrides for Grafana Alloy. Keep the base
  recipe unchanged. Alloy scrapes every 60 seconds and owns remote-write credentials
  and a persistent WAL; its management endpoint is not published.
- Keep dashboard import manual. The application has no Grafana write credentials and
  monitoring failures do not affect application startup or business work.

## Consequences

PromEx and its transitive packages are included in releases even with collection
turned off. Enabling metrics adds in-memory series, polling work, an authenticated
HTTP endpoint and, optionally, an Alloy container with disk/network usage. Application
histograms use coarse buckets and no diagnostic labels to contain cardinality.

The 8,000-sample scrape guard and stable instance label help limit usage but do not
ensure a Cloud account stays within its free allowance. Operators must measure their
usage after representative activity. WAL buffering has bounded retention and does
not guarantee lossless delivery. Alloy has an explicit lifecycle separate from the
shared application release commands. See the [operator guide](../../deploy/compose/monitoring.md).

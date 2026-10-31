# 0026. Dashboard as code with explicit publication

Status: Implemented and published to Grafana Cloud. The dashboard content is intentionally minimal and grows as needed.

## Context

Decision [0023](0023-project-overview-monitoring.md) produced a single project
overview covering every context, framework boundary, and optional Docker
collector. In daily home use it became too dense, and its builder depended on
the previous generated JSON as a template. Decision
[0021](0021-optional-prometheus-metrics.md) kept publication manual, so the
repository and Grafana Cloud could drift unless an operator imported the file
again by hand.

The operator wants a small overview that grows one section at a time, and a
reproducible command that publishes it.

## Decision

- Replace the existing overview with `Bolognesa · Overview`, starting from the
  BEAM runtime and optional Docker resource sections only. Add further
  functionality when it proves useful, not preemptively.
- Keep the dashboard as a declarative Python specification rendered to
  `grafana/dashboards/overview.json`. The generated JSON is committed, remains
  a portable import template with `${DS_PROMETHEUS}`, and does not depend on a
  previous dashboard or a Mix invocation.
- Publish explicitly with a local script that resolves the Prometheus
  datasource UID and calls the Grafana API with `overwrite: true`. The stable
  UID makes publication idempotent; `--dry-run` shows the resolved payload.
- Keep Grafana API credentials in an ignored `.env.grafana` file, separate from
  the metrics and logs tokens used by Alloy. The application and CI never hold
  dashboard credentials and never publish.
- Keep the PromEx dashboard exports as generated import templates. The new
  publication flow applies to the project overview; manual import remains a
  fallback.

## Consequences

Publishing requires a local service-account token and the stack's Prometheus
datasource UID. The generated file stays free of private stack identifiers, so
it can be reviewed and shared. Skipping publication leaves the committed
dashboard ahead of Grafana Cloud, and the publisher reports the resulting
version so that difference remains visible.

The new dashboard intentionally omits context, HTTP, LiveView, Ecto, and Oban
sections. Those metrics remain exported and available in the PromEx dashboards;
they are absent from the overview until added deliberately. The old
`bolognesa-operational` dashboard must be removed manually after verifying the
new UID.

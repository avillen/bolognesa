# Optional metrics with PromEx and Grafana Cloud

Bolognesa works without Prometheus, Grafana, Alloy, or a Cloud account. By default,
PromEx collection is disabled, `/metrics` returns 404, and the base Compose recipe
runs only the application and PostgreSQL. Existing logs and LiveDashboard remain
available. There are no outgoing monitoring requests in this configuration.

Opting in uses this pipeline:

```text
Bolognesa Telemetry → PromEx /metrics → Alloy → Grafana Cloud Metrics
```

Alloy scrapes every 60 seconds and sends Prometheus remote write over HTTPS. Grafana
credentials live in Alloy, not in the application. No logs, traces, host metrics,
Docker socket, or media mounts are collected by Alloy.

## Enable on an installation

1. Obtain the Prometheus remote-write URL, numeric username, and a stack-scoped
   access-policy token with `metrics:write` from your Grafana Cloud stack's
   **Send metrics / Details** page. These are separate from Grafana dashboard API
   credentials. See [Grafana's Prometheus guide](https://grafana.com/docs/grafana-cloud/send-data/metrics/metrics-prometheus/).
2. Append the settings from [monitoring.env.example](monitoring.env.example) to the
   target server's ignored `.env`. Generate a separate scrape token with
   `openssl rand -hex 32`. Use a stable, public-safe instance name, distinct for each
   installation writing to the same stack. Keep `.env` private (`chmod 600 .env`).
3. Append `monitoring.yaml` to your existing `DEPLOY_COMPOSE_FILES` in `.env.deploy`.
   Preserve all current networking, storage and media overrides. For host networking,
   append `monitoring.host.yaml` as well, after `network.host.yaml` and
   `monitoring.yaml`. It follows `BOLOGNESA_BIND_IP` and `BOLOGNESA_PORT`; a wildcard bind
   (`0.0.0.0`) is scraped through `127.0.0.1`.

Examples of file selection (retain any additional existing overrides):

```make
# Bridge networking:
DEPLOY_COMPOSE_FILES=compose.yaml:monitoring.yaml
# Linux host networking:
DEPLOY_COMPOSE_FILES=compose.yaml:network.host.yaml:monitoring.yaml:monitoring.host.yaml
```

4. Follow the [shared deployment workflow](README.md) to upload the selected files
   and deploy a published application release that includes PromEx. Alloy's config
   is embedded in the override, so there is no separate config file to upload.
   `make deploy-release` updates the application; it does not start extra services.
5. On the target server, from its deployment directory, use the same selected files
   to start Alloy explicitly. For bridge networking:

```sh
docker compose -f compose.yaml -f monitoring.yaml up -d --no-deps alloy
```

Include your other selected `-f` overrides, especially both host-network files when
applicable. Repeat this command after changing Alloy configuration, credentials or
image version. Alloy has no published ports; its management listener binds loopback
inside its network namespace. Its named volume retains the write-ahead log across
container replacements. Do not use `down -v` on an existing installation.

Cloud outages or rejected writes do not block the application. Alloy retries using
its WAL, with an eight-hour maximum retention window; this is best effort rather
than lossless delivery. Resource limits are initial budgets, not measured requirements.

## Verify and investigate

On the server, using the same Compose file selection:

```sh
docker compose -f compose.yaml -f monitoring.yaml ps alloy
docker compose -f compose.yaml -f monitoring.yaml logs --tail 100 alloy
```

The unauthenticated `/metrics` response should be 401 after activation. A request
with `Authorization: Bearer <scrape token>` returns Prometheus text. Use your secret
manager or a private curl configuration file for authenticated manual checks; do not
paste tokens into shell history or commit them. Before activation the response is 404.

In Grafana Explore, choose the stack's Prometheus data source and query:

```promql
up{job="bolognesa"}
```

It should be 1 for your instance after a successful scrape. A value of 0 means Alloy
could send samples but could not scrape the application; no series can also indicate
remote-write authentication or network failure. Check Alloy logs for 401/403 responses,
DNS/TLS failures, and scrape sample-limit errors.

Run representative workflows, then inspect application observations, for example:

```promql
rate(bolognesa_libraries_scan_completed_count{job="bolognesa"}[5m])
```

Operational counters use existing fixed event names and have no metadata labels.
Duration histograms end in `_duration_milliseconds` and use buckets of 10, 100, 1000,
10000, 60000 and 300000 ms, plus infinity. They receive samples only when the owning
event supplies `duration_ms`; starts and outcomes are independent observations.

Framework metrics cover application information, BEAM, Phoenix HTTP, Ecto and Oban.
HTTP paths are route templates or `Unknown`; client host labels are removed and
unrecognized HTTP methods become `OTHER`. Phoenix channel/socket and LiveView event
metrics are omitted to avoid client-controlled event labels. Diagnostic IDs, raw
URLs, query parameters, media names, SQL text and exception messages are not exported.
Framework labels still include configured database names/hosts, module names and
Oban node names; review those values before sharing metrics publicly.

## Dashboards

The application never uploads dashboards or needs a Grafana service-account token.
From a development checkout, export the bundled PromEx dashboards for manual import.
Use the exact Prometheus data source name shown in your Grafana stack:

```sh
mkdir -p tmp/grafana-dashboards
mix compile
mix help prom_ex.dashboard.export
mix prom_ex.dashboard.export \
  --module Bolognesa.Infrastructure.Observability.PromEx \
  --dashboard beam.json --stdout \
  --assign datasource_id=YOUR_PROMETHEUS_DATASOURCE_NAME \
  > tmp/grafana-dashboards/beam.json
```

Repeat for `application.json`, `phoenix.json`, `ecto.json`, and `oban.json`. In Grafana,
use **Dashboards → New → Import**, upload the JSON, and select your data source.
The Phoenix dashboard's URL and channel/socket panels remain empty because those
metrics are intentionally omitted. Application workflow counters/histograms can be graphed
in separate panels using their `bolognesa_` names.

## Free-plan budget

Grafana currently advertises 10,000 billable metric series and 14-day retention for
its [free plan](https://grafana.com/get/). Verify the limits in your account when
activating it. The 60-second interval reduces sample volume; it does not reduce the
number of distinct label combinations. Histograms generate multiple series.

Alloy rejects an entire scrape above 8,000 samples to leave headroom for its scrape
health metrics. This is a per-scrape guard, not a Cloud quota guarantee: other sources,
multiple installations and series churn share the account budget. Monitor Grafana's
usage page after representative activity. Keep instance labels stable and review
series usage before adding collectors or tags.

## Disable or use another collector

Stop Alloy explicitly with the same Compose files before removing the monitoring
overrides, then redeploy the application with the original file selection. The
exporter returns to its default disabled state; retain the Alloy volume unless you
intentionally want to discard buffered samples. The shared `deploy-stop` command
stops app/db only, so stop Alloy separately for full shutdown.

To use an existing collector instead, omit Alloy and set
`BOLOGNESA_METRICS_ENABLED=true` and `BOLOGNESA_METRICS_TOKEN` (at least 32 bytes) in the
application process environment. For Compose, forward those values through your own
app override; unrelated `.env` variables are not automatically passed to containers.
Scrape `/metrics` using the bearer credential over a trusted private connection.

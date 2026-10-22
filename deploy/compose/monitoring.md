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
Docker socket, or media mounts are collected by the metrics-only Alloy service.

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

## Optional application logs with Loki

Logs are a separate opt-in. Omitting `monitoring.loki.yaml` leaves the metrics-only
setup unchanged; an ordinary installation needs neither Loki credentials nor a Docker
socket mount. When selected, a dedicated `alloy-logs` service reads only containers
labelled by this Compose override, currently just Bolognesa's `app` service, and sends
them to Grafana Cloud Loki. PostgreSQL and Alloy logs are not collected. The pipeline
uses only the fixed `service` and `instance` labels, and its Docker read positions persist
in a separate named volume. Remote log delivery remains best effort; Loki's optional
Alloy WAL is experimental and is not enabled here.

The Docker socket gives its holder broad control of the Docker daemon even when mounted
read-only. This permission exists only on `alloy-logs`, which is created only when this
override is selected. Include it only on a host where that access is acceptable.

1. In Grafana Cloud's Cloud Portal, open your stack, select **Loki → Details**, and copy
   the endpoint URL and numeric **User**. Create a stack-scoped access-policy token with
   `logs:write`; keep it separate from the metrics token. Alloy needs the full push URL:
   append `/loki/api/v1/push` to the copied endpoint unless it already ends with that
   path. Use the endpoint shown in your portal rather than guessing its hostname.
2. Add the Loki variables from [monitoring.env.example](monitoring.env.example) to the
   target server's ignored `.env`: `GRAFANA_CLOUD_LOKI_URL`,
   `GRAFANA_CLOUD_LOKI_USERNAME`, and `GRAFANA_CLOUD_LOKI_TOKEN`. Keep `.env` private.
   Set a stable, public-safe `BOLOGNESA_LOGS_INSTANCE` if several installations share
   the same stack. The resource limits shown in the example are starting budgets.
3. Append `monitoring.loki.yaml` after `compose.yaml` in `DEPLOY_COMPOSE_FILES`. For an
   installation already using metrics, append it after the existing monitoring files.
   Preserve all existing network, storage, and media overrides. For example:

```make
# Logs only, bridge networking:
DEPLOY_COMPOSE_FILES=compose.yaml:monitoring.loki.yaml
# Logs plus metrics, Linux host networking:
DEPLOY_COMPOSE_FILES=compose.yaml:network.host.yaml:monitoring.yaml:monitoring.host.yaml:monitoring.loki.yaml
```

4. Use the shared deployment workflow to upload the selected Compose file and recreate
   the app so Compose applies its opt-in log label. Then start the collector explicitly
   with the complete selected file list, including all installation-specific overrides:

```sh
docker compose -f compose.yaml -f monitoring.loki.yaml up -d --no-deps alloy-logs
```

`make deploy-release` updates the application but does not start optional collectors.
Repeat the `up` command after changing Loki credentials or the Alloy config. Do not use
`down -v`; it would remove persistent application data and buffered log positions.

In Grafana Explore, select the stack's Loki data source and query:

```logql
{service="bolognesa", instance="bolognesa"}
```

Replace the instance value if you configured another name. Run an application workflow
to create a fresh log entry. Docker log rotation bounds local history, and this setup
does not promise backfilling logs from before activation. Check
`docker compose ... ps alloy-logs` and `docker compose ... logs --tail 100 alloy-logs`
for collector health and rejected writes. To disable log forwarding, stop `alloy-logs`
and remove `monitoring.loki.yaml` from the selected files; keep the volume if you may
enable it again.

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
Duration histograms end in `_duration_milliseconds`. Buckets distinguish short operations
(1 ms to 5 minutes), scans (10 ms to 1 hour), and session lifetime (1 second to 3 hours),
plus infinity. They receive samples only when the owning event supplies `duration_ms`;
starts and outcomes are independent observations. Existing event counters stay unlabelled.
Three additional Playback counters have bounded diagnostic, FFmpeg result, or closure-reason
labels; they contain no session/file/tab identifiers.

Framework metrics cover application information, BEAM, Phoenix HTTP, Ecto and Oban.
HTTP paths are route templates or `Unknown`; client host labels are removed and
unrecognized HTTP methods become `OTHER`. Phoenix channel/socket metrics are omitted. An adapter around
`PromEx.Plugins.PhoenixLiveView` exports mount and event-handler durations and exceptions,
and adds the same measurements for parameter handling and rendering. Only a fixed view
allowlist and its context are labels; unknown views become `global` / `other`. Client event
names, parameters, exception details, and URLs are never labels. Timings describe server
callbacks, not browser rendering or total page-interaction latency. Ecto duration buckets
include submillisecond queries; framework metric names remain compatible. Diagnostic IDs, raw
URLs, query parameters, media names, SQL text and exception messages are not exported.
Framework labels still include configured database names/hosts, module names and
Oban node names; review those values before sharing metrics publicly.

## Dashboards

The application never uploads dashboards or needs a Grafana service-account token.
The repository keeps Grafana import JSON in `grafana/dashboards/`. The five framework
dashboards are generated from the pinned PromEx dependency; the operational dashboard is
maintained in the repository and queries Bolognesa's fixed event metrics. To regenerate
the PromEx dashboards after a dependency update, run from a development checkout:

```sh
python3 scripts/export-grafana-dashboards.py
```

The script writes `application.json`, `beam.json`, `phoenix.json`, `ecto.json`, and
`oban.json` as Grafana datasource-selection templates. Review and commit regenerated
files together with the dependency change. `operational.json` is generated from the application's event catalog and the project-owned
layout/query definitions. Regenerate it with:

```sh
python3 scripts/build-operational-dashboard.py
python3 test/grafana/overview-test.py
# Optional PromQL checks against empty data and sparse histograms with a counter reset:
docker run --rm -v "$PWD/tmp/operational-overview:/config:ro" --entrypoint /bin/promtool \
  prom/prometheus:v3.5.0 test rules /config/queries.json
```

Import `operational.json` through **Dashboards → New → Import** and select the stack's
Prometheus data source. Its stable UID replaces the earlier operational dashboard.
Publishing remains manual; regenerating source does not change Grafana Cloud.

The project overview has an expanded summary and collapsed detail rows for Accounts,
Libraries, Movies, Series, Music, Playback, global Phoenix/LiveView, Ecto, Oban, BEAM,
and optional Docker. Expand a context to inspect functionality outcomes, rolling activity,
measured-operation counts, mean, p50, and p95. The default time range is 24 hours;
**Activity / latency window** independently selects 15 minutes, 1 hour (default), 6 hours,
or 24 hours for trend estimates. Stats explicitly labelled selected range cover the whole
range; resource gauges show current samples. Collapsed rows defer diagnostic query loading.

Interpretation:

- Counts use Prometheus `increase`, not exact durable event totals. Sparse activity,
  extrapolation, restarts, or events before the first scrape can produce fractions or
  undercounts. Starts, retries and outcomes are distinct observations, never summed into
  a claimed number of completed workflows. No data is not displayed as healthy zero.
- Duration sample counts accompany operational timings. Quantiles are bucket estimates;
  p50 and p95 can coincide with very few samples. The mean uses measured sums/counts.
  Operational timings combine measured outcomes within one functionality; session duration
  is lifetime until close, not preparation time. Logs remain the source for a specific
  execution. When upgrading buckets, use a range entirely after the rollout; mixed old
  and new bucket layouts distort historical quantiles until the old samples leave the window.
- HTTP ownership follows route templates; direct/HLS media requests belong to Playback.
  LiveView ownership follows its fixed screen module, so player interactions on movie or
  episode screens remain with Movies/Series. HTTP does not count WebSocket interactions.
- Ecto ownership follows the primary source table reported by Ecto; joins do not establish
  caller ownership. Playback reads content-owned tables and has no persistence table of its
  own. The global row includes all queries, connection queue/decode/idle time, and shared or
  unclassified sources. Query errors have a dedicated counter, `bolognesa_prom_ex_ecto_repo_query_errors_total`,
  filtered on Ecto error results with repo/source labels. Command `unavailable` remains
  an unclassified command, not an error classification. Pool size is configuration,
  not connection occupancy.
- Oban processing follows worker ownership; Movies and Series share a queue. Queue gauges,
  concurrency, exceptions and circuit breakers also have a global row. Exceptions describe
  attempts and do not necessarily indicate a persisted terminal failure.
- Playback diagnostics are best effort and retain the existing 120-observation cap per
  LiveView lifetime. Browser waits/errors and FFmpeg exit results are distinct signals.

The five bundled PromEx dashboards remain available for detailed framework exploration.
The Phoenix dashboard's URL and channel/socket panels remain empty because those metrics
are intentionally omitted.

## Optional Docker resources on native Linux

`monitoring.docker.yaml` adds a separate `alloy-docker` service using the pinned Alloy
cAdvisor exporter. It is intended for a native Linux Docker host; Docker Desktop host
resource monitoring is not supported by this recipe. See the
[Alloy cAdvisor reference](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.cadvisor/).
The collector runs privileged and mounts the Docker socket and host filesystem read-only,
plus `/sys` and `/var/lib/docker`. The optional `/dev/disk` device-name mapping is not
mounted, so the recipe also works on hosts without that directory. These give broad host access even though
forwarded metrics are filtered. Forwarded metrics exclude media inventories, application logs, environment variables,
image labels, and arbitrary container labels. Metrics-only
Alloy and the application receive no additional permissions or mounts.

1. Append `monitoring.docker.yaml` to the existing selected Compose files, preserving all
   current overrides. Reuse the metrics remote-write credentials. `COMPOSE_PROJECT_NAME`
   must match the installation; `BOLOGNESA_METRICS_INSTANCE` must match the app scrape.
   If Docker uses a custom data root, set `BOLOGNESA_DOCKER_DATA_ROOT` to its native host path.
2. Upload the selected files using the shared deployment workflow, then start the new
   collector explicitly, with the complete selected file list. For bridge networking:

```sh
docker compose -f compose.yaml -f monitoring.yaml -f monitoring.docker.yaml up -d --no-deps --force-recreate alloy-docker
```

For a host-network installation include `network.host.yaml` and `monitoring.host.yaml`;
the Docker collector itself retains bridge networking. It has no published management port.
Use `--force-recreate` after config changes so an existing container cannot retain the old
embedded config mount. Its persistent WAL survives recreation.
`make deploy-release` does not start optional collectors.

Only containers from the selected Compose project and services `app`, `db`, `alloy`,
`alloy-logs`, and `alloy-docker` are forwarded. The allowlist retains CPU usage, working-set
memory/limit, network bytes, block-I/O bytes, last-seen and start timestamps, plus scrape
health. Labels are job, instance, service, sanitized runtime container ID (for recreation
and replica separation), CPU, interface, and device. Runtime IDs add churn; account for
this when measuring series use. Raw cgroup paths, container/image names and Compose project
labels are removed. Scrapes happen every 60 seconds with an 8,000-sample guard **before**
forwarding filters; a host with many unrelated containers can exceed it even though their
metrics would not be forwarded. Project/service filtering limits forwarding, not host access.

Check collector logs and query both signals:

```promql
up{job="bolognesa-docker", instance="bolognesa"}
container_last_seen{job="bolognesa-docker", instance="bolognesa"}
```

A successful scrape does not prove cAdvisor discovered containers; look for fresh
last-seen samples for the expected services. CPU is measured in cores and includes FFmpeg
inside the app container. Host-network traffic can represent shared host counters; do not
sum it as independent container traffic. Storage-driver support controls block-I/O availability;
it does not report library free capacity. Start timestamps are not durable restart counts.
Limits shown in `monitoring.env.example` are starting budgets, not measured requirements.
Native ARM64 collection and target-host resource accuracy require installation verification.

Stop `alloy-docker` explicitly before removing the override to disable it. Its dedicated WAL
volume is independent of app/database data. Never use `down -v` on an existing installation.

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

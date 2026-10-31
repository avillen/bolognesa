# Grafana dashboards

Generated Grafana JSON lives in `dashboards/`. The application never uploads
dashboards and never holds Grafana credentials.

## Generate

```sh
make grafana-build                          # overview + checks
python3 grafana/export-promex-dashboards.py # five PromEx dashboards
```

`grafana/build-overview.py` renders `dashboards/overview.json` from the rows and
panels declared in the same file. The output keeps `${DS_PROMETHEUS}` so it also
works as an import template. Commit the generated file with its generator.

## Publish the overview

Create `.env.grafana` in the repository root, ignored by Git and readable only
by you (`chmod 600`):

```sh
GRAFANA_URL=https://example.grafana.net
GRAFANA_TOKEN=replace-with-a-service-account-token
GRAFANA_PROMETHEUS_UID=replace-with-the-stack-prometheus-datasource-uid
# GRAFANA_FOLDER_UID=optional-folder-uid
```

`GRAFANA_TOKEN` needs permission to write dashboards and is separate from the
Alloy metrics and logs tokens. Exported environment variables take precedence
over the file. The token is never printed.

```sh
python3 grafana/publish-dashboard.py --dry-run   # writes tmp/grafana/overview-resolved.json
make grafana-publish
```

The publisher replaces the datasource placeholder, removes import-only fields,
and overwrites the dashboard with the same UID. It prints the resulting version
and URL. Manual import through **Dashboards → New → Import** remains a fallback.

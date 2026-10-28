#!/usr/bin/env python3
"""Export the bundled PromEx dashboards as Grafana import templates."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "grafana" / "dashboards"
PROM_EX_MODULE = "Bolognesa.Infrastructure.Observability.PromEx"
DASHBOARDS = ("application", "beam", "phoenix", "ecto", "oban")
DATASOURCE = "DS_PROMETHEUS"


def replace_datasource(value: object) -> object:
    if isinstance(value, dict):
        return {key: replace_datasource(item) for key, item in value.items()}
    if isinstance(value, list):
        return [replace_datasource(item) for item in value]
    if value == DATASOURCE:
        return "${DS_PROMETHEUS}"
    return value


def export_dashboard(name: str) -> dict[str, object]:
    result = subprocess.run(
        [
            "mix",
            "prom_ex.dashboard.export",
            "--module",
            PROM_EX_MODULE,
            "--dashboard",
            f"{name}.json",
            "--stdout",
            "--assign",
            f"datasource_id={DATASOURCE}",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    dashboard = json.loads(result.stdout)
    dashboard = replace_datasource(dashboard)
    dashboard["__inputs"] = [
        {
            "name": DATASOURCE,
            "label": "Prometheus",
            "description": "Prometheus-compatible metrics data source",
            "type": "datasource",
            "pluginId": "prometheus",
            "pluginName": "Prometheus",
        }
    ]
    return dashboard


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in DASHBOARDS:
        dashboard = export_dashboard(name)
        path = OUTPUT / f"{name}.json"
        path.write_text(json.dumps(dashboard, indent=2) + "\n", encoding="utf-8")
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()

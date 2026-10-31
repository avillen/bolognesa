#!/usr/bin/env python3
"""Build the Bolognesa overview from a declarative panel specification."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'grafana/dashboards/overview.json'
DS = {'type': 'prometheus', 'uid': '${DS_PROMETHEUS}'}
BEAM = 'bolognesa_prom_ex_beam'
BEAM_SCOPE = 'job="$job", instance="$instance"'
DOCKER_SCOPE = 'job="bolognesa-docker", instance="$instance"'
JOB_VARIABLE = {
    'allValue': None, 'datasource': '${DS_PROMETHEUS}',
    'definition': 'label_values(bolognesa_prom_ex_prom_ex_status_info, job)',
    'hide': 0, 'includeAll': False, 'label': 'Prometheus Job', 'multi': False,
    'name': 'job', 'options': [],
    'query': 'label_values(bolognesa_prom_ex_prom_ex_status_info, job)',
    'refresh': 2, 'regex': '', 'skipUrlSync': False, 'sort': 6,
    'tagValuesQuery': '', 'tags': [], 'tagsQuery': '', 'type': 'query',
    'useTags': False,
}
INSTANCE_VARIABLE = {
    'allValue': None, 'datasource': '${DS_PROMETHEUS}',
    'definition': 'label_values(bolognesa_prom_ex_prom_ex_status_info, instance)',
    'hide': 0, 'includeAll': False, 'label': 'Application Instance', 'multi': False,
    'name': 'instance', 'options': [],
    'query': 'label_values(bolognesa_prom_ex_prom_ex_status_info{job="$job"}, instance)',
    'refresh': 2, 'regex': '', 'skipUrlSync': False, 'sort': 0,
    'tagValuesQuery': '', 'tags': [], 'tagsQuery': '', 'type': 'query',
    'useTags': False,
}


def beam(name):
    return f'{BEAM}_{name}{{{BEAM_SCOPE}}}'


def beam_rate(name):
    return f'rate({beam(name)}[$__rate_interval])'


def docker(name):
    return f'{name}{{{DOCKER_SCOPE}}}'


LIMIT_OVERRIDES = [
    {
        'matcher': {'id': 'byRegexp', 'options': '.* · limit'},
        'properties': [
            {'id': 'custom.lineStyle', 'value': {'fill': 'dash', 'dash': [10, 10]}},
            {'id': 'custom.fillOpacity', 'value': 0},
            {'id': 'color', 'value': {'mode': 'fixed', 'fixedColor': '#8a8a8a'}},
        ],
    }
]


ROWS = [
    {
        'title': 'BEAM · runtime resources',
        'collapsed': False,
        'panels': [
            {
                'title': 'Uptime', 'unit': 'ms', 'kind': 'stat',
                'queries': [(beam('stats_uptime_milliseconds_count'), 'Uptime')],
            },
            {
                'title': 'Memory', 'unit': 'bytes',
                'queries': [
                    (beam(name), f'{name} {{{{type}}}}')
                    for name in (
                        'memory_allocated_bytes', 'memory_processes_total_bytes',
                        'memory_binary_total_bytes', 'memory_ets_total_bytes',
                        'memory_atom_total_bytes', 'memory_code_total_bytes',
                    )
                ],
            },
            {
                'title': 'Processes / ports / ETS',
                'queries': [
                    (beam(name), f'{name} {{{{type}}}}')
                    for name in ('stats_process_count', 'stats_port_count', 'stats_ets_count')
                ],
            },
            {
                'title': 'Scheduler work and run queues',
                'queries': [
                    (beam(name), f'{name} {{{{type}}}}')
                    for name in ('stats_active_task_count', 'stats_run_queue_count')
                ],
            },
            {
                'title': 'Atoms',
                'queries': [
                    (beam(name), f'{name} {{{{type}}}}')
                    for name in ('stats_atom_count', 'system_atom_limit_info')
                ],
            },
            {
                'title': 'Garbage collections', 'unit': 'ops',
                'queries': [(beam_rate('stats_gc_count'), '{{type}}')],
            },
            {
                'title': 'GC reclaimed bytes', 'unit': 'Bps',
                'queries': [(beam_rate('stats_gc_reclaimed_bytes'), '{{type}}')],
            },
            {
                'title': 'Reductions', 'unit': 'ops',
                'queries': [(beam_rate('stats_reduction_count'), '{{type}}')],
            },
            {
                'title': 'Port I/O', 'unit': 'Bps',
                'queries': [(beam_rate('stats_port_io_byte_count'), '{{type}}')],
            },
        ],
    },
    {
        'title': 'Docker · optional Linux collector',
        'collapsed': True,
        'panels': [
            {
                'title': 'Docker collector scrape', 'kind': 'stat',
                'queries': [(f'up{{{DOCKER_SCOPE}}}', 'Scrape')],
                'description': 'Requires monitoring.docker.yaml on native Linux. No data means absent or unavailable collection, not zero resource use. The exporter may be up even when container discovery fails.',
            },
            {
                'title': 'Containers observed recently', 'kind': 'stat',
                'queries': [(f'count by (service) ({docker("container_last_seen")} > time() - 180)', '{{service}}')],
                'description': 'At least one fresh container sample per service. Missing service requires investigation; scrape success alone is insufficient.',
            },
            {
                'title': 'CPU · cores used',
                'queries': [(f'sum by (service) (rate({docker("container_cpu_usage_seconds_total")}[$__rate_interval]))', '{{service}}')],
                'description': 'One unit is one CPU core. Includes FFmpeg subprocesses in the app container.',
            },
            {
                'title': 'Memory · usage vs limit', 'unit': 'bytes', 'width': 12,
                'queries': [
                    (f'sum by (service) ({docker("container_memory_working_set_bytes")})', '{{service}} · usage'),
                    (f'max by (service) ({docker("container_spec_memory_limit_bytes")})', '{{service}} · limit'),
                ],
                'description': 'Working set is current usage summed by service; the dashed line is the configured container limit. Unlimited containers can report the host limit. Limits are per container, so replicas would make the sum and max incomparable.',
                'overrides': LIMIT_OVERRIDES,
            },
            {
                'title': 'Network · receive / transmit', 'unit': 'Bps', 'width': 12,
                'queries': [
                    (f'sum by (service) (rate({docker(metric)}[$__rate_interval]))', f'{{{{service}}}} · {label}')
                    for metric, label in (
                        ('container_network_receive_bytes_total', 'RX'),
                        ('container_network_transmit_bytes_total', 'TX'),
                    )
                ],
                'description': 'Per-container network counters. Host-network containers can share host counters; values must not be summed into a host total.',
            },
            {
                'title': 'Block I/O · read / write', 'unit': 'Bps', 'width': 12,
                'queries': [
                    (f'sum by (service) (rate({docker(metric)}[$__rate_interval]))', f'{{{{service}}}} · {label}')
                    for metric, label in (
                        ('container_fs_reads_bytes_total', 'read'),
                        ('container_fs_writes_bytes_total', 'write'),
                    )
                ],
                'description': 'Block I/O exposed by the runtime; may be absent depending on storage driver. Does not measure media capacity or free space.',
            },
            {
                'title': 'Container starts', 'unit': 'dateTimeAsIso', 'kind': 'stat',
                'width': 12,
                'queries': [(f'max by (service) ({docker("container_start_time_seconds")}) * 1000', '{{service}}')],
                'description': 'Most recent container start timestamp. This is not a durable restart counter.',
            },
        ],
    },
]


class Dashboard:
    def __init__(self):
        self.panels = []
        self.y = 0
        self.x = 0
        self.height = 0

    def next_line(self):
        self.y += self.height
        self.x = self.height = 0

    def row(self, title, collapsed):
        self.next_line()
        self.panels.append({
            'id': len(self.panels) + 1, 'type': 'row', 'title': title,
            'collapsed': collapsed, 'panels': [],
            'gridPos': {'x': 0, 'y': self.y, 'w': 24, 'h': 1},
        })
        self.y += 1

    def panel(self, title, queries, unit='short', kind='timeseries',
              width=None, description='', height=None, overrides=None):
        width = width or 8
        height = height or 4
        if self.x + width > 24:
            self.next_line()
        defaults = {'unit': unit, 'noValue': 'No data', 'color': {'mode': 'palette-classic'}}
        if kind == 'timeseries':
            defaults['custom'] = {
                'drawStyle': 'line', 'lineWidth': 1, 'fillOpacity': 8,
                'showPoints': 'auto', 'spanNulls': False,
            }
        options = (
            {
                'reduceOptions': {'calcs': ['lastNotNull'], 'fields': '', 'values': False},
                'colorMode': 'none', 'graphMode': 'none', 'textMode': 'auto',
                'orientation': 'auto', 'justifyMode': 'auto',
            }
            if kind == 'stat'
            else {
                'legend': {'displayMode': 'table', 'placement': 'bottom', 'calcs': ['lastNotNull']},
                'tooltip': {'mode': 'multi', 'sort': 'desc'},
            }
        )
        self.panels.append({
            'id': len(self.panels) + 1, 'type': kind, 'title': title,
            'description': description, 'datasource': DS,
            'gridPos': {'x': self.x, 'y': self.y, 'w': width, 'h': height},
            'fieldConfig': {'defaults': defaults, 'overrides': overrides or []},
            'options': options,
            'targets': [
                {
                    'refId': f'Q{i}', 'expr': expr, 'legendFormat': label,
                    'editorMode': 'code', 'instant': kind == 'stat',
                    'range': kind != 'stat',
                }
                for i, (expr, label) in enumerate(queries)
            ],
        })
        self.x += width
        self.height = max(self.height, height)


def group_collapsed(panels):
    grouped = []
    active_row = None
    for panel in panels:
        if panel['type'] == 'row':
            active_row = panel
            grouped.append(panel)
        elif active_row and active_row['collapsed']:
            active_row['panels'].append(panel)
        else:
            grouped.append(panel)
    return grouped


def build():
    dashboard = Dashboard()
    for row in ROWS:
        dashboard.row(row['title'], row['collapsed'])
        for panel in row['panels']:
            dashboard.panel(**panel)
    return {
        '__inputs': [
            {
                'name': 'DS_PROMETHEUS', 'label': 'Prometheus',
                'description': 'Prometheus-compatible metrics data source',
                'type': 'datasource', 'pluginId': 'prometheus',
                'pluginName': 'Prometheus',
            }
        ],
        'annotations': {
            'list': [
                {
                    'builtIn': 1,
                    'datasource': {'type': 'grafana', 'uid': '-- Grafana --'},
                    'enable': True, 'hide': True,
                    'iconColor': 'rgba(0, 211, 255, 1)',
                    'name': 'Annotations & Alerts', 'type': 'dashboard',
                }
            ]
        },
        'description': 'BEAM runtime and optional Docker resources for a low-traffic home installation. Missing data is never healthy zero.',
        'editable': True,
        'fiscalYearStartMonth': 0,
        'graphTooltip': 1,
        'links': [],
        'liveNow': False,
        'panels': group_collapsed(dashboard.panels),
        'refresh': '1m',
        'schemaVersion': 39,
        'tags': ['bolognesa', 'operations'],
        'templating': {'list': [JOB_VARIABLE, INSTANCE_VARIABLE]},
        'time': {'from': 'now-24h', 'to': 'now'},
        'timezone': 'browser',
        'title': 'Bolognesa · Overview',
        'uid': 'bolognesa-overview',
        'version': 1,
        'weekStart': '',
    }


if __name__ == '__main__':
    OUTPUT.write_text(json.dumps(build(), indent=2) + '\n')
    print(OUTPUT.relative_to(ROOT))

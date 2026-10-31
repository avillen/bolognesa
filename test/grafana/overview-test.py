#!/usr/bin/env python3
"""Check the generated overview's scope, layout and queries without network access."""

import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
BUILDER = ROOT / 'grafana/build-overview.py'


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


module = load_module(BUILDER, 'overview')
dashboard = module.build()
assert dashboard == module.build(), 'Build must be deterministic'
assert dashboard == json.loads(module.OUTPUT.read_text()), 'Regenerate overview.json'
assert dashboard['uid'] == 'bolognesa-overview'
assert dashboard['title'] == 'Bolognesa · Overview'
assert dashboard['time']['from'] == 'now-24h'
assert dashboard['__inputs'][0]['name'] == 'DS_PROMETHEUS'

rows = [p for p in dashboard['panels'] if p['type'] == 'row']
assert [row['title'] for row in rows] == [
    'BEAM · runtime resources',
    'Docker · optional Linux collector',
]
assert [row['collapsed'] for row in rows] == [False, True]

panels = dashboard['panels'] + [p for row in rows for p in row.get('panels', [])]
assert len({panel['id'] for panel in panels}) == len(panels)

for panel in panels:
    if panel['type'] == 'row':
        continue
    assert panel['fieldConfig']['defaults']['noValue'] == 'No data', panel['title']
    assert panel['gridPos']['x'] + panel['gridPos']['w'] <= 24, panel['title']
    assert panel['targets'], panel['title']
    for target in panel['targets']:
        assert target['expr'], panel['title']
        assert 'or vector(0)' not in target['expr'], panel['title']

for index, row in enumerate(rows):
    row_y = row['gridPos']['y']
    if row['collapsed']:
        children = row.get('panels', [])
    else:
        next_y = rows[index + 1]['gridPos']['y'] if index + 1 < len(rows) else float('inf')
        children = [
            panel for panel in dashboard['panels']
            if panel['type'] != 'row' and row_y < panel['gridPos']['y'] < next_y
        ]
    lines = {}
    for child in children:
        lines.setdefault(child['gridPos']['y'], []).append(child)
    assert lines, row['title']
    for y, line in lines.items():
        assert sum(child['gridPos']['w'] for child in line) == 24, (row['title'], y)
        assert {child['gridPos']['h'] for child in line} == {8}, (row['title'], y)

queries = [target['expr'] for panel in panels for target in panel.get('targets', [])]
for metric in (
    'bolognesa_prom_ex_beam_stats_uptime_milliseconds_count',
    'bolognesa_prom_ex_beam_memory_allocated_bytes',
    'bolognesa_prom_ex_beam_stats_process_count',
    'bolognesa_prom_ex_beam_stats_gc_count',
    'container_last_seen',
    'container_cpu_usage_seconds_total',
    'up{job="bolognesa-docker"',
):
    assert any(metric in query for query in queries), metric

assert not any('bolognesa_libraries_' in query for query in queries)
assert not any('$window' in query for query in queries)
print('overview checks passed')

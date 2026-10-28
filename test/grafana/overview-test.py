#!/usr/bin/env python3
"""Check overview coverage, sparse-data semantics, layout and generated queries.

Writes a Promtool rule-test fixture under the requested directory for parser/type checks.
"""
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('overview', ROOT / 'scripts/monitoring/build-overview-dashboard.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
events = module.catalog()
dashboard = json.loads(module.OUTPUT.read_text())
assert dashboard == module.build(events), 'Regenerate the overview after changing its generator or events'
assert dashboard['time']['from'] == 'now-24h'
rows = [p for p in dashboard['panels'] if p['type'] == 'row']
assert len(rows) == 12
assert all(p['collapsed'] for p in rows if p['title'] != 'Overview')
panels = dashboard['panels'] + [p for row in rows for p in row.get('panels', [])]
assert len({p['id'] for p in panels}) == len(panels)
queries = [t['expr'] for p in panels for t in p.get('targets', [])]
for event in events:
    counter = '_'.join(event) + '_count'
    assert any(counter in q for q in queries), counter
for panel in panels:
    if panel['type'] == 'row':
        continue
    assert panel['fieldConfig']['defaults']['noValue'] == 'No data'
    assert panel['gridPos']['x'] + panel['gridPos']['w'] <= 24
    assert not any('or vector(0)' in t['expr'] or 'irate(' in t['expr'] for t in panel['targets'])
    if 'duration' in panel['title'].lower() and panel['fieldConfig']['defaults']['unit'] == 'ms' and panel['type'] == 'timeseries':
        assert {t['legendFormat'] for t in panel['targets']} == {'Mean', 'p50', 'p95'}, panel['title']
for row in rows:
    children = row.get('panels', [])
    for i, p in enumerate(children):
        a = p['gridPos']
        for other in children[i+1:]:
            b = other['gridPos']
            assert a['x'] + a['w'] <= b['x'] or b['x'] + b['w'] <= a['x'] or a['y'] + a['h'] <= b['y'] or b['y'] + b['h'] <= a['y'], (p['title'], other['title'])
# Empty input must stay empty, and every query must parse/type-check in Prometheus.
replacements = {'$__rate_interval': '5m', '$__range': '24h', '$window': '1h', '$job': 'bolognesa', '$instance': 'bolognesa'}
expressions = []
for query in queries:
    for source, target in replacements.items():
        query = query.replace(source, target)
    expressions.append({'expr': query, 'eval_time': '24h', 'exp_samples': []})
output = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'tmp/operational-overview')
output.mkdir(parents=True, exist_ok=True)
fixture = {'rule_files': [], 'evaluation_interval': '1m', 'tests': [{'interval': '1m', 'promql_expr_test': expressions}]}
(output / 'queries.json').write_text(json.dumps(fixture, indent=2) + '\n')
print(f'Overview: {len(rows)} rows, {len(panels) - len(rows)} panels, {len(events)} event counters, {len(queries)} PromQL queries checked structurally')
# Populated sparse traffic, including a counter reset: mean and estimated quantiles
# must remain meaningful, with unrelated contexts/instances excluded.
metric = 'bolognesa_libraries_scan_completed_duration_milliseconds'
labels = 'job="bolognesa",instance="bolognesa"'
series = [
    {'series': metric + '_count{' + labels + '}', 'values': '0+1x30 0+1x29'},
    {'series': metric + '_sum{' + labels + '}', 'values': '0+20x30 0+20x29'},
    {'series': metric + '_bucket{' + labels + ',le="10"}', 'values': '0+0x60'},
    {'series': metric + '_bucket{' + labels + ',le="25"}', 'values': '0+1x30 0+1x29'},
    {'series': metric + '_bucket{' + labels + ',le="+Inf"}', 'values': '0+1x30 0+1x29'},
    {'series': metric + '_count{job="bolognesa",instance="another"}', 'values': '0+100x60'},
]
latency_panel = next(p for p in panels if p['title'] == 'Scan · duration')
populated = []
for target, expected in zip(latency_panel['targets'], [20, 17.5, 24.25]):
    query = target['expr']
    for source, replacement in replacements.items():
        query = query.replace(source, replacement)
    populated.append({'expr': query, 'eval_time': '1h', 'exp_samples': [{'labels': '{}', 'value': expected}]})
fixture['tests'].append({'interval': '1m', 'input_series': series, 'promql_expr_test': populated})
(output / 'queries.json').write_text(json.dumps(fixture, indent=2) + '\n')

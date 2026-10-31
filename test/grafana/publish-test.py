#!/usr/bin/env python3
"""Check environment loading and dashboard resolution without network access."""

import importlib.util
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
PUBLISHER = ROOT / 'grafana/publish-dashboard.py'
PLACEHOLDER = '${DS_PROMETHEUS}'


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


module = load_module(PUBLISHER, 'publisher')

with tempfile.TemporaryDirectory() as directory:
    env_file = Path(directory) / '.env.grafana'
    env_file.write_text(
        '# comment\n'
        'GRAFANA_URL=https://file.example\n'
        'GRAFANA_TOKEN=file-token\n'
        'GRAFANA_PROMETHEUS_UID=file-uid\n'
        'GRAFANA_FOLDER_UID=folder\n'
    )
    values = module.load_env(env_file, {'GRAFANA_TOKEN': 'env-token'})
    assert values['GRAFANA_URL'] == 'https://file.example'
    assert values['GRAFANA_TOKEN'] == 'env-token'
    assert values['GRAFANA_PROMETHEUS_UID'] == 'file-uid'
    assert values['GRAFANA_FOLDER_UID'] == 'folder'

original = {'panel': {'datasource': {'uid': PLACEHOLDER}}, 'list': [PLACEHOLDER]}
resolved = module.resolve(original, 'prom-uid')
assert resolved == {'panel': {'datasource': {'uid': 'prom-uid'}}, 'list': ['prom-uid']}
assert original['panel']['datasource']['uid'] == PLACEHOLDER

body = module.payload({'uid': 'x', 'id': 7, '__inputs': [{}]}, 'prom-uid', 'message')
assert body['dashboard'] == {'uid': 'x'}
assert body['overwrite'] is True
assert body['message'] == 'message'
print('publish checks passed')

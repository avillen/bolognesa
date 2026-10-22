#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
root = Path('deploy/compose')
env = dict(os.environ, SECRET_KEY_BASE='synthetic', POSTGRES_PASSWORD='synthetic',
           BOLOGNESA_METRICS_TOKEN='synthetic-scrape-token-with-32-bytes',
           GRAFANA_CLOUD_METRICS_URL='https://prometheus.example.invalid/api/prom/push',
           GRAFANA_CLOUD_METRICS_USERNAME='12345', GRAFANA_CLOUD_METRICS_TOKEN='synthetic-cloud-token',
           BOLOGNESA_PORT='4400', BOLOGNESA_BIND_IP='127.0.0.1')
keys = ('BOLOGNESA_METRICS_TOKEN', 'GRAFANA_CLOUD_METRICS_URL',
        'GRAFANA_CLOUD_METRICS_USERNAME', 'GRAFANA_CLOUD_METRICS_TOKEN')
def config(files, variables):
    command = ['docker', 'compose', '--env-file', str(root/'.env.example')]
    for name in files:
        command += ['-f', str(root/name)]
    return subprocess.run(command+['config', '--format', 'json'], env=variables, capture_output=True, text=True)
plain = dict(env)
for key in keys: plain.pop(key, None)
result = config(['compose.yaml'], plain)
assert result.returncode == 0, result.stderr
base = json.loads(result.stdout)
assert set(base['services']) == {'app', 'db'}
assert 'BOLOGNESA_METRICS_ENABLED' not in base['services']['app']['environment']
for host in (False, True):
    files = ['compose.yaml', 'monitoring.yaml']
    if host: files += ['network.host.yaml', 'monitoring.host.yaml']
    result = config(files, env)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    app, alloy = data['services']['app'], data['services']['alloy']
    assert app['environment']['BOLOGNESA_METRICS_ENABLED'] == 'true'
    assert app['environment']['BOLOGNESA_METRICS_TOKEN'] == env['BOLOGNESA_METRICS_TOKEN']
    assert not alloy.get('ports')
    assert 'GRAFANA_CLOUD_METRICS_TOKEN' not in app['environment']
    assert alloy['environment']['BOLOGNESA_METRICS_TARGET'] == ('127.0.0.1:4400' if host else 'app:4000')
    assert alloy['volumes'][0]['target'] == '/var/lib/alloy/data'
    content = data['configs']['alloy_config']['content']
    assert 'scrape_interval = "60s"' in content
    assert 'sample_limit = 8000' in content
    assert 'string.replace(sys.env("BOLOGNESA_METRICS_TARGET"), "0.0.0.0:", "127.0.0.1:")' in content
    assert 'synthetic-cloud-token' not in content
    if host: assert alloy['network_mode'] == 'host'
    for key in keys:
        missing = dict(env); missing[key] = ''
        failed = config(files, missing)
        assert failed.returncode != 0 and key in failed.stderr, (key, failed.stderr)

for bind in ('192.0.2.20', '0.0.0.0'):
    host_env = dict(env, BOLOGNESA_BIND_IP=bind)
    result = config(['compose.yaml', 'network.host.yaml', 'monitoring.yaml', 'monitoring.host.yaml'], host_env)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    app_env = data['services']['app']['environment']
    alloy_env = data['services']['alloy']['environment']
    assert app_env['BIND_IP'] == bind
    assert alloy_env['BOLOGNESA_METRICS_TARGET'] == bind + ':4400', (bind, alloy_env['BOLOGNESA_METRICS_TARGET'])
print('Optional monitoring configuration passed: base, bridge, host and missing credentials')
PY

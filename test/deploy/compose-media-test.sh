#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import json, os, subprocess, tempfile
from pathlib import Path

root = Path('deploy/compose')
env = dict(os.environ, SECRET_KEY_BASE='synthetic', POSTGRES_PASSWORD='synthetic',
           MEDIA_AUTOMATION_DATA_PATH='/srv/shared media', MEDIA_AUTOMATION_CONFIG_PATH='/srv/arr config',
           MEDIA_AUTOMATION_PUID='1234', MEDIA_AUTOMATION_PGID='2345',
           SONARR_IMAGE='lscr.io/linuxserver/sonarr:test', RADARR_IMAGE='lscr.io/linuxserver/radarr:test',
           PROWLARR_IMAGE='lscr.io/linuxserver/prowlarr:test')
required = ('MEDIA_AUTOMATION_DATA_PATH', 'MEDIA_AUTOMATION_CONFIG_PATH',
            'MEDIA_AUTOMATION_PUID', 'MEDIA_AUTOMATION_PGID', 'SONARR_IMAGE', 'RADARR_IMAGE', 'PROWLARR_IMAGE')
def config(files, variables):
    command = ['docker', 'compose', '--env-file', str(root/'.env.example')]
    for name in files:
        command += ['-f', str(root/name)]
    return subprocess.run(command+['config', '--format', 'json'], env=variables, capture_output=True, text=True)

for host in (False, True):
    base_files = ['compose.yaml'] + (['network.host.yaml'] if host else [])
    base = config(base_files, env)
    assert base.returncode == 0, base.stderr
    base = json.loads(base.stdout)
    files = base_files + ['media-automation.yaml']
    result = config(files, env)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert set(data['services']) == {'app', 'db', 'sonarr', 'radarr', 'prowlarr'}
    for name in ('app', 'db'):
        assert data['services'][name] == base['services'][name], name
    for name, port in (('sonarr', 8989), ('radarr', 7878), ('prowlarr', 9696)):
        service = data['services'][name]
        assert service.get('network_mode') != 'host'
        assert service['ports'][0]['host_ip'] == '127.0.0.1'
        assert service['ports'][0]['target'] == port
        assert service['environment']['PUID'] == '1234'
        assert service['environment']['PGID'] == '2345'
        assert service['environment']['UMASK'] == '002'
        mounts = {m['target']: m for m in service['volumes']}
        assert mounts['/config']['source'] == '/srv/arr config/' + name
        assert all(m['bind']['create_host_path'] is False for m in mounts.values())
        if name == 'prowlarr':
            assert set(mounts) == {'/config'}
        else:
            assert mounts['/data']['source'] == '/srv/shared media'
            assert not mounts['/data'].get('read_only', False)
    for key in required:
        missing = dict(env); missing[key] = ''
        failed = config(files, missing)
        assert failed.returncode != 0 and key in failed.stderr, (key, failed.stderr)
custom = dict(env, MEDIA_AUTOMATION_BIND_IP='192.0.2.20', SONARR_PORT='18989', RADARR_PORT='17878', PROWLARR_PORT='19696')
result = config(['compose.yaml', 'media-automation.yaml'], custom)
assert result.returncode == 0, result.stderr
services = json.loads(result.stdout)['services']
for name, port in (('sonarr', '18989'), ('radarr', '17878'), ('prowlarr', '19696')):
    assert services[name]['ports'][0]['host_ip'] == '192.0.2.20'
    assert str(services[name]['ports'][0]['published']) == port
print('Optional media configuration passed: bridge, host app, preserved mounts, required settings and private ports')

# Exercise real operation dispatch at the Docker boundary without starting services.
with tempfile.TemporaryDirectory() as directory:
    target = Path(directory)
    (target/'.env').write_text('')
    (target/'compose.yaml').write_text('')
    docker = target/'docker'
    docker.write_text('''#!/bin/sh
set -eu
shift
while [ "$#" -gt 0 ]; do
  case "$1" in -f|--env-file|--project-directory) shift 2 ;; *) break ;; esac
done
printf '%s\\n' "$*" >> "$TRACE"
case "$*" in pull*) [ "${FAIL_PULL:-no}" != yes ] ;; esac
''')
    docker.chmod(0o700)
    trace = target/'trace'
    runtime = dict(os.environ, DEPLOY_DIR=directory, DOCKER_BIN=str(docker),
                   COMPOSE_FILE='compose.yaml', TRACE=str(trace))
    expected = {
        'media-up': ['config --quiet', 'pull sonarr radarr prowlarr',
                     'up -d --no-deps sonarr radarr prowlarr', 'ps sonarr radarr prowlarr'],
        'media-status': ['config --quiet', 'ps sonarr radarr prowlarr'],
        'media-stop': ['config --quiet', 'stop sonarr radarr prowlarr'],
        'media-logs': ['config --quiet', 'logs --tail 100 --follow sonarr radarr prowlarr'],
    }
    for operation, commands in expected.items():
        trace.write_text('')
        result = subprocess.run(['sh', str(root/'scripts/operate.sh'), operation],
                                env=runtime, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert trace.read_text().splitlines() == commands
    trace.write_text('')
    result = subprocess.run(['sh', str(root/'scripts/operate.sh'), 'media-up'],
                            env=dict(runtime, FAIL_PULL='yes'), capture_output=True, text=True)
    assert result.returncode != 0
    assert trace.read_text().splitlines() == ['config --quiet', 'pull sonarr radarr prowlarr']
print('Media operations passed: scoped lifecycle and failed-pull protection')
PY

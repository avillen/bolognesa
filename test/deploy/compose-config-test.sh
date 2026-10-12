#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import json, os, subprocess
from pathlib import Path
root = Path('deploy/compose')
env = dict(os.environ, SECRET_KEY_BASE='synthetic', POSTGRES_PASSWORD='synthetic',
           POSTGRES_DATA_PATH='/srv/example/postgres', MOVIES_PATH='/srv/movies',
           SERIES_PATH='/srv/series', DB_PORT='55432', BOLOGNESA_PORT='4400')
for network in ('bridge', 'host'):
    for storage in ('volume', 'bind'):
        files = [root/'compose.yaml']
        if network == 'host': files.append(root/'network.host.yaml')
        if storage == 'bind': files.append(root/'storage.bind.yaml')
        files.append(root/'media.example.yaml')
        assert all(f.exists() for f in files), f'Missing configurable recipes: {files}'
        cmd = ['docker','compose','--env-file',str(root/'.env.example')]
        for f in files: cmd.extend(['-f',str(f)])
        result = subprocess.run(cmd+['config','--format','json'],env=env,capture_output=True,text=True)
        assert result.returncode == 0, result.stderr
        c = json.loads(result.stdout); app=c['services']['app']; db=c['services']['db']
        assert not db.get('ports'), db
        assert all(v['read_only'] for v in app['volumes']), app['volumes']
        assert {v['target'] for v in app['volumes']} == {'/media/movies','/media/series'}
        assert app['environment']['BOLOGNESA_LIBRARY_ROOTS'] == '/media/movies:/media/series'
        assert db['volumes'][0]['type'] == storage
        # Compose 2 omits false JSON fields; Compose 5 serializes them explicitly.
        if storage == 'bind': assert not db['volumes'][0].get('bind', {}).get('create_host_path', False)
        if network == 'host':
            assert app['network_mode'] == db['network_mode'] == 'host'
            assert not app.get('ports')
            assert '@127.0.0.1:55432/' in app['environment']['DATABASE_URL']
            assert 'listen_addresses=127.0.0.1' in db['command']
            assert app['environment']['PORT'] == '4400'
            assert '55432' in ' '.join(db['healthcheck']['test'])
        else:
            assert app['ports'][0]['host_ip'] == '127.0.0.1'
            assert app['ports'][0]['published'] == '4400'
            assert '@db:5432/' in app['environment']['DATABASE_URL']
        for missing in ('SECRET_KEY_BASE','POSTGRES_PASSWORD'):
            bad = dict(env); bad[missing]=''
            result=subprocess.run(cmd+['config','--quiet'],env=bad,capture_output=True,text=True)
            assert result.returncode != 0 and missing in result.stderr
print('Compose configuration matrix passed')
PY

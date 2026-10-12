#!/usr/bin/env python3
"""Opt-in real Docker smoke test, using only a uniquely named synthetic project."""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
scratch = repo / 'tmp' / 'deployment-integration'
scratch.mkdir(parents=True, exist_ok=True)
target = Path(tempfile.mkdtemp(prefix='synthetic-', dir=scratch))
project = 'bolognesa-check-' + secrets.token_hex(5)
image = os.environ.get('DEPLOY_TEST_IMAGE', 'bolognesa-app:latest')
port = os.environ.get('DEPLOY_TEST_PORT', '18473')
env = dict(os.environ, DEPLOY_TRANSPORT='local', DEPLOY_DIR=str(target),
           COMPOSE_FILE='compose.yaml', DEPLOY_HEALTH_URL=f'http://127.0.0.1:{port}/')
compose = ['docker', 'compose', '--env-file', str(target/'.env'), '-f', str(target/'compose.yaml')]

def run(args, **kw):
    result = subprocess.run(args, env=env, text=True, capture_output=True, **kw)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode})\n{result.stderr[-4000:]}\n{result.stdout[-4000:]}')
    return result.stdout.strip()

def operation(name, *args):
    return run(['bash', str(repo/'deploy/compose/scripts/deploy.sh'), name, *args])

def sql(statement):
    return run(compose+['exec','-T','db','psql','-U','bolognesa','-d','bolognesa','-Atc',statement])

try:
    operation('upload')
    media=target/'media'; media.mkdir(); media.chmod(0o755)
    target.chmod(0o755)
    (media/'synthetic.txt').write_text('read-only original')
    values=dict(BOLOGNESA_IMAGE=image, SECRET_KEY_BASE=secrets.token_hex(64),
                POSTGRES_PASSWORD=secrets.token_hex(32), PHX_HOST='127.0.0.1',
                BOLOGNESA_PORT=port, PUBLIC_PORT=port, MEDIA_PATH=str(media),
                COMPOSE_PROJECT_NAME=project, DATA_ROOT=str(target))
    (target/'.env').write_text('\n'.join(f'{k}={v}' for k,v in values.items())+'\n')
    (target/'.env').chmod(0o600)
    operation('install', image)
    sql('CREATE TABLE deployment_check(value integer); INSERT INTO deployment_check VALUES (42);')
    backup=operation('backup')
    assert Path(backup).stat().st_size > 0
    operation('update', image)
    assert sql('SELECT value FROM deployment_check') == '42'
    sql('UPDATE deployment_check SET value=99')
    # Explicit automation confirmation applies only to this synthetic database.
    run(['sh',str(target/'scripts/restore.sh'),backup,'--yes'])
    assert sql('SELECT value FROM deployment_check') == '42'
    app_id=run(compose+['ps','-a','-q','app'])
    inspect=json.loads(run(['docker','inspect',app_id]))[0]
    assert not inspect['State']['Running']
    mount=next(m for m in inspect['Mounts'] if m['Destination']=='/media')
    assert not mount['RW']
    assert (media/'synthetic.txt').read_text() == 'read-only original'
    print('Real Docker install/backup/update/restore passed; synthetic data and read-only media preserved')
finally:
    if (target/'.env').exists():
        # Only this random project can be removed; never the operator's installation.
        assert project.startswith('bolognesa-check-')
        subprocess.run(compose+['down','-v'],env=env,capture_output=True,check=True)
    shutil.rmtree(target)

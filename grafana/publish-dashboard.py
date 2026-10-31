#!/usr/bin/env python3
"""Publish a generated dashboard to Grafana Cloud over the HTTP API."""

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FILE = ROOT / 'grafana/dashboards/overview.json'
ENV_FILE = ROOT / '.env.grafana'
PLACEHOLDER = '${DS_PROMETHEUS}'
REQUIRED = ('GRAFANA_URL', 'GRAFANA_TOKEN', 'GRAFANA_PROMETHEUS_UID')


def load_env(path=ENV_FILE, environ=None):
    environ = os.environ if environ is None else environ
    values = {}
    if Path(path).exists():
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    for key in REQUIRED + ('GRAFANA_FOLDER_UID',):
        if key in environ:
            values[key] = environ[key]
    return values


def resolve(value, datasource_uid):
    if isinstance(value, dict):
        return {key: resolve(item, datasource_uid) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item, datasource_uid) for item in value]
    return datasource_uid if value == PLACEHOLDER else value


def payload(document, datasource_uid, message, folder_uid=None):
    dashboard = resolve(document, datasource_uid)
    dashboard.pop('__inputs', None)
    dashboard.pop('id', None)
    body = {'dashboard': dashboard, 'overwrite': True, 'message': message}
    if folder_uid:
        body['folderUid'] = folder_uid
    return body


def current_commit():
    try:
        result = subprocess.run(
            ['git', 'rev-parse', '--short', 'HEAD'],
            cwd=ROOT, check=True, capture_output=True, text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return 'unknown'
    return result.stdout.strip()


def publish(body, url, token, timeout=30):
    request = urllib.request.Request(
        url.rstrip('/') + '/api/dashboards/db',
        data=json.dumps(body).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {token}',
        },
        method='POST',
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('file', nargs='?', type=Path, default=DEFAULT_FILE)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--message', default=None)
    args = parser.parse_args(argv)

    values = load_env()
    needed = ('GRAFANA_URL', 'GRAFANA_PROMETHEUS_UID') if args.dry_run else REQUIRED
    missing = [key for key in needed if not values.get(key)]
    if missing:
        parser.error('missing ' + ', '.join(missing) + ' in the environment or .env.grafana')

    document = json.loads(args.file.read_text())
    message = args.message or f'publish {args.file.name} @ {current_commit()}'
    body = payload(document, values['GRAFANA_PROMETHEUS_UID'], message,
                   values.get('GRAFANA_FOLDER_UID'))

    if args.dry_run:
        output = ROOT / 'tmp/grafana' / f'{args.file.stem}-resolved.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(body, indent=2) + '\n')
        print(output.relative_to(ROOT))
        print('dry run; no request sent to', values['GRAFANA_URL'])
        return 0

    try:
        result = publish(body, values['GRAFANA_URL'], values['GRAFANA_TOKEN'])
    except urllib.error.HTTPError as error:
        detail = error.read().decode('utf-8', errors='replace')[:500]
        print(f'Grafana API returned {error.code}: {detail}', file=sys.stderr)
        return 1
    except urllib.error.URLError as error:
        print(f'Could not reach Grafana: {error.reason}', file=sys.stderr)
        return 1

    print(f"published uid={result.get('uid')} version={result.get('version')} status={result.get('status')}")
    print(values['GRAFANA_URL'].rstrip('/') + result.get('url', ''))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

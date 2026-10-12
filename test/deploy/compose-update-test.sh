#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
cat > "$test_dir/bin/docker" <<'MOCK'
#!/bin/sh
set -eu
if [ "${1:-}" = compose ]; then
 shift
 while [ "${1:-}" = --env-file ] || [ "${1:-}" = -f ] || [ "${1:-}" = --project-directory ]; do shift 2; done
 set -- compose "$@"
fi
case "$*" in
  pull*) echo pull >> "$MOCK_TRACE" ;;
  'image inspect'*) echo arm64 ;;
  'inspect --format'*)
    case "$*" in *Health*) echo healthy ;; *Running*) if [ "$MOCK_FAIL" = stopped-backup ]; then echo false; else echo true; fi ;; *Image*) echo "$MOCK_OLD_IMAGE" ;; *) echo /existing/database ;; esac ;;
  'compose ps -a -q db') test "$MOCK_FAIL" != missing-db && echo db-id ;;
  'compose ps -a -q app') echo app-id ;;
  'compose config --hash db') echo 'db stable-hash' ;;
  'compose exec -T db pg_restore --list'*) : ;;
  'compose stop app') echo stop >> "$MOCK_TRACE" ;;
  'compose exec -T db'*)
    echo backup >> "$MOCK_TRACE"
    test "$MOCK_FAIL" != backup && test "$MOCK_FAIL" != stopped-backup || exit 1
    echo 'synthetic nonempty dump'
    ;;
  'compose run --rm --no-deps app /app/bin/migrate')
    echo migrate >> "$MOCK_TRACE"
    test "$MOCK_FAIL" != migration || exit 1
    ;;
  'compose up -d --force-recreate app') echo "activate:${BOLOGNESA_IMAGE:-unset}" >> "$MOCK_TRACE" ;;
  *) : ;;
esac
MOCK
cat > "$test_dir/bin/curl" <<'MOCK'
#!/bin/sh
set -eu
echo http >> "$MOCK_TRACE"
test "$MOCK_FAIL" != http || exit 22
printf '200'
MOCK
chmod +x "$test_dir/bin/docker" "$test_dir/bin/curl"
export PATH="$test_dir/bin:$PATH" DEPLOY_HTTP_RETRIES=0
image=ghcr.io/avillen/bolognesa-lan@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
old=ghcr.io/avillen/bolognesa-lan@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
for phase in success backup migration http missing-db config-change stopped-backup; do
  dir="$test_dir/$phase"
  mkdir -p "$dir/backups"
  printf 'BOLOGNESA_IMAGE=%s\n' "$old" > "$dir/.env"
  touch "$dir/compose.yaml"
  printf "db stable-hash\n" > "$dir/.database-config"
  if [ "$phase" = config-change ]; then printf "db previous-hash\n" > "$dir/.database-config"; fi
  export MOCK_TRACE="$dir/trace" MOCK_FAIL="$phase" MOCK_OLD_IMAGE="$old"
  touch "$MOCK_TRACE"
  if DEPLOY_DIR="$dir" DOCKER_BIN="$test_dir/bin/docker" DEPLOY_HEALTH_URL=http://localhost:4000 sh "$repo_dir/deploy/compose/scripts/operate.sh" update "$image" > "$dir/result" 2>&1; then
    [[ $phase == success ]] || { echo "Expected failure: $phase"; exit 1; }
  else
    [[ $phase != success ]] || { cat "$dir/result"; exit 1; }
  fi
  python3 - "$MOCK_TRACE" "$phase" "$image" "$old" "$dir" <<'PY'
import pathlib,sys
trace,phase,image,old,directory=sys.argv[1:]
steps=pathlib.Path(trace).read_text().splitlines()
if phase in ('missing-db', 'config-change'):
    assert 'stop' not in steps and 'migrate' not in steps, steps
    assert pathlib.Path(directory,'.env').read_text() == 'BOLOGNESA_IMAGE='+old+'\n'
    sys.exit(0)
assert steps.index('stop') < steps.index('backup'), steps
if phase == 'success':
    assert steps.index('backup') < steps.index('migrate') < steps.index('activate:'+image) < steps.index('http'), steps
    assert pathlib.Path(directory,'.env').read_text() == 'BOLOGNESA_IMAGE='+image+'\n'
    backups=list(pathlib.Path(directory,'backups').glob('*.dump'))
    assert len(backups)==1 and backups[0].stat().st_size>0
    assert pathlib.Path(str(backups[0])+'.image-ref').read_text() == old+'\n'
elif phase == 'stopped-backup':
    assert 'migrate' not in steps and 'activate:'+old not in steps, steps
    assert steps[-1] == 'stop', steps
elif phase == 'backup':
    assert 'migrate' not in steps and steps[-1] == 'activate:'+old, steps
else:
    assert 'activate:'+old not in steps and steps[-1] == 'stop', steps
    assert pathlib.Path(directory,'.env').read_text() == 'BOLOGNESA_IMAGE='+old+'\n'
    assert any(p.stat().st_size>0 for p in pathlib.Path(directory,'backups').glob('*.dump'))
PY
done
echo 'Compose update failure and recovery tests passed'

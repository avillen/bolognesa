#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
cat > "$test_dir/bin/docker" <<'MOCK'
#!/bin/sh
set -eu
case "$*" in
  pull*) echo pull >> "$MOCK_TRACE" ;;
  'image inspect'*) echo arm64 ;;
  'inspect --format'*) echo healthy ;;
  'compose stop app') echo stop >> "$MOCK_TRACE" ;;
  'compose exec -T db'*)
    echo backup >> "$MOCK_TRACE"
    test "$MOCK_FAIL" != backup || exit 1
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
test "$MOCK_FAIL" != http || exit 22
printf '200'
MOCK
chmod +x "$test_dir/bin/docker" "$test_dir/bin/curl"
export PATH="$test_dir/bin:$PATH"
image=ghcr.io/avillen/bolognesa-lan@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
old=ghcr.io/avillen/bolognesa-lan@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
for phase in success backup migration http; do
  dir="$test_dir/$phase"
  mkdir -p "$dir/backups"
  printf 'BOLOGNESA_IMAGE=%s\n' "$old" > "$dir/.env"
  touch "$dir/compose.yaml"
  export MOCK_TRACE="$dir/trace" MOCK_FAIL="$phase"
  if sh "$repo_dir/deploy/qnap/scripts/apply-image.sh" "$image" "$dir" "$test_dir/bin/docker" localhost 4000 > "$dir/result" 2>&1; then
    [[ $phase == success ]] || { echo "Expected failure: $phase"; exit 1; }
  else
    [[ $phase != success ]] || { cat "$dir/result"; exit 1; }
  fi
  python3 - "$MOCK_TRACE" "$phase" "$image" "$old" "$dir" <<'PY'
import pathlib,sys
trace,phase,image,old,directory=sys.argv[1:]
steps=pathlib.Path(trace).read_text().splitlines()
assert steps.index('stop') < steps.index('backup'), steps
if phase == 'success':
    assert steps.index('backup') < steps.index('migrate') < steps.index('activate:'+image), steps
    assert pathlib.Path(directory,'.env').read_text() == 'BOLOGNESA_IMAGE='+image+'\n'
    backups=list(pathlib.Path(directory,'backups').glob('*.dump'))
    assert len(backups)==1 and backups[0].stat().st_size>0
    assert pathlib.Path(str(backups[0])+'.image-ref').read_text() == old+'\n'
elif phase == 'backup':
    assert 'migrate' not in steps and steps[-1] == 'activate:'+old, steps
else:
    assert 'activate:'+old not in steps and steps[-1] == 'stop', steps
    assert pathlib.Path(directory,'.env').read_text() == 'BOLOGNESA_IMAGE='+old+'\n'
    assert any(p.stat().st_size>0 for p in pathlib.Path(directory,'backups').glob('*.dump'))
PY
done
echo 'qnap apply image tests passed'

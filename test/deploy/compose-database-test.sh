#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/installation"
touch "$test_dir/installation/.env" "$test_dir/installation/compose.yaml"
cat > "$test_dir/bin/docker" <<'SH'
#!/bin/sh
set -eu
if [ "$1" = compose ]; then
  shift
  while [ "${1:-}" = -f ] || [ "${1:-}" = --env-file ] || [ "${1:-}" = --project-directory ]; do shift 2; done
  case "$*" in
    'ps -a -q db') [ "$CASE" = present ] && echo current-db; exit 0 ;;
    'up -d db') echo recreated-db >> "$TRACE" ;;
    'exec -T db sh -c'*) echo dump >> "$TRACE"; echo synthetic ;;
  esac
elif [ "$1" = inspect ]; then echo healthy
elif [ "$1" = start ]; then echo started-existing-db >> "$TRACE"
fi
SH
chmod +x "$test_dir/bin/docker"
export DEPLOY_DIR="$test_dir/installation" DOCKER_BIN="$test_dir/bin/docker" TRACE="$test_dir/trace"
export CASE=present
sh "$repo_dir/deploy/compose/scripts/backup.sh" >/dev/null
if grep -q recreated-db "$TRACE"; then echo 'Backup recreated the database using changed configuration' >&2; exit 1; fi
: > "$TRACE"
export CASE=missing
if sh "$repo_dir/deploy/compose/scripts/backup.sh" >/dev/null 2>&1; then echo 'Backup created a missing database' >&2; exit 1; fi
test ! -s "$TRACE"
echo 'Backup uses the existing database without reconfiguration'

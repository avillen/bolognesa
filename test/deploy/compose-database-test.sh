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
    'config --environment')
      printf 'POSTGRES_DATA_PATH=%s\n' "${PRIVATE_DATABASE_PATH:-}"
      printf 'MEDIA_AUTOMATION_DATA_PATH=%s\n' "${MEDIA_AUTOMATION_DATA_PATH:-}"
      printf 'MEDIA_AUTOMATION_CONFIG_PATH=%s\n' "${MEDIA_AUTOMATION_CONFIG_PATH:-}"
      ;;
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
mkdir "$test_dir/private-postgres"
chmod 000 "$test_dir/private-postgres"
export PRIVATE_DATABASE_PATH="$test_dir/private-postgres"
trap 'chmod 700 "$test_dir/private-postgres"; rm -rf "$test_dir"' EXIT
sh "$repo_dir/deploy/compose/scripts/operate.sh" preflight >/dev/null
# Disabling optional services must leave ordinary application preflight usable,
# even when their old storage settings remain in the runtime environment.
MEDIA_AUTOMATION_DATA_PATH="$test_dir/removed-media-data" \
MEDIA_AUTOMATION_CONFIG_PATH="$test_dir/removed-media-config" \
  sh "$repo_dir/deploy/compose/scripts/operate.sh" preflight >/dev/null
cat > "$test_dir/bin/df" <<'SH'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
printf 'synthetic 1000000 999999 %s 0%% /\n' "${FAKE_FREE_KIB:-999999}"
SH
chmod +x "$test_dir/bin/df"
export PATH="$test_dir/bin:$PATH" FAKE_FREE_KIB=1
if sh "$repo_dir/deploy/compose/scripts/operate.sh" preflight >/dev/null 2>&1; then
  echo 'Preflight accepted insufficient backup/image space' >&2; exit 1
fi
echo 'Existing database and configurable storage preflight passed'

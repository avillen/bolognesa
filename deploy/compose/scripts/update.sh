#!/bin/sh
set -eu
. "$(dirname -- "$0")/common.sh"
. "$script_dir/backup-lock.sh"
require_runtime
sh "$script_dir/prune-backups.sh" --check
operation=${DEPLOY_OPERATION:-update}
image_ref=${1:-}
test -n "${DEPLOY_HEALTH_URL:-}" || { echo 'Set DEPLOY_HEALTH_URL' >&2; exit 2; }
db_id=$(database_id)
if [ "$operation" = update ]; then
  test -n "$db_id" || { echo 'Update requires an existing database; use install for a new deployment' >&2; exit 1; }
  db_hash=$(compose config --hash db)
  if [ ! -f .database-config ] || [ "$(cat .database-config)" != "$db_hash" ]; then
    if [ "${ALLOW_DATABASE_CONFIG_CHANGE:-no}" != yes ]; then
      echo 'Database configuration changed or has no baseline; verify storage, then set ALLOW_DATABASE_CONFIG_CHANGE=yes and EXPECTED_DATABASE_SOURCE' >&2
      exit 1
    fi
    test -n "${EXPECTED_DATABASE_SOURCE:-}" || { echo 'Missing EXPECTED_DATABASE_SOURCE' >&2; exit 1; }
    current_source=$("$DOCKER_BIN" inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}{{end}}{{end}}' "$db_id")
    test "$current_source" = "$EXPECTED_DATABASE_SOURCE" || { echo 'Database storage differs from the expected existing source' >&2; exit 1; }
  fi
else
  test -z "$db_id" || { echo 'Installation already exists; use update' >&2; exit 1; }
fi
old_image=; old_running=false
if [ -n "$image_ref" ]; then
  "$DOCKER_BIN" image inspect "$image_ref" >/dev/null 2>&1 || "$DOCKER_BIN" pull "$image_ref"
else
  image_ref=$(runtime_value BOLOGNESA_IMAGE)
  test -n "$image_ref"
  compose pull app
fi
export BOLOGNESA_IMAGE="$image_ref"
compose config --quiet
compose up -d db
wait_database
app_stopped=0; migration_started=0; env_tmp=
finish() {
  result=$?
  trap - 0
  if [ "$result" -ne 0 ] && [ "$app_stopped" -eq 1 ]; then
    if [ "$migration_started" -eq 0 ] && [ "$old_running" = true ] && [ -n "$old_image" ]; then
      BOLOGNESA_IMAGE="$old_image" compose up -d --force-recreate app || echo 'Previous app could not be restored' >&2
    else
      compose stop app || true
      if [ "$migration_started" -eq 1 ]; then
        echo 'Migration began; app remains stopped. Inspect schema and backup before recovery.' >&2
      else
        echo 'Deployment failed before migration; app remains stopped.' >&2
      fi
    fi
  fi
  if [ -n "$env_tmp" ]; then rm -f "$env_tmp"; fi
  backup_lock_release
  exit "$result"
}
trap finish 0
umask 077
backup_lock_acquire "${DEPLOY_BACKUP_DIR:-$DEPLOY_DIR/backups}"
old_app=$(compose ps -a -q app)
if [ -n "$old_app" ]; then
  old_image=$("$DOCKER_BIN" inspect --format '{{.Config.Image}}' "$old_app")
  old_running=$("$DOCKER_BIN" inspect --format '{{.State.Running}}' "$old_app")
fi
app_stopped=1
compose stop app
backup=$(DEPLOY_BACKUP_PRUNE=no "$script_dir/backup.sh" "${DEPLOY_BACKUP_DIR:-$DEPLOY_DIR/backups}")
umask 077
printf '%s\n' "$old_image" > "$backup.image-ref"
migration_started=1
compose run --rm --no-deps app /app/bin/migrate
compose up -d --force-recreate app
verify_http
env_tmp=".env.image.$$"
awk '!/^BOLOGNESA_IMAGE=/' .env > "$env_tmp"
printf 'BOLOGNESA_IMAGE=%s\n' "$image_ref" >> "$env_tmp"
chmod 600 "$env_tmp"
mv "$env_tmp" .env
env_tmp=
compose config --hash db > .database-config.tmp
mv .database-config.tmp .database-config
app_stopped=0
sh "$script_dir/prune-backups.sh" "${DEPLOY_BACKUP_DIR:-$DEPLOY_DIR/backups}" "${backup##*/}" >&2
compose ps
printf 'Image deployed: %s\nDatabase backup: %s\n' "$image_ref" "$backup"

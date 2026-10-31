#!/bin/sh
set -eu
. "$(dirname -- "$0")/common.sh"
. "$script_dir/backup-lock.sh"
require_runtime
sh "$script_dir/prune-backups.sh" --check
backup_dir=${1:-${DEPLOY_BACKUP_DIR:-$DEPLOY_DIR/backups}}
umask 077
mkdir -p "$backup_dir"
temporary_file=
finish() {
  if [ -n "$temporary_file" ]; then rm -f "$temporary_file"; fi
  backup_lock_release
}
trap finish 0
backup_lock_acquire "$backup_dir"
wait_database
temporary_file=$(mktemp "${backup_dir%/}/.bolognesa-backup.XXXXXX")
compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$temporary_file"
test -s "$temporary_file"
compose exec -T db pg_restore --list < "$temporary_file" >/dev/null
backup_file="${backup_dir%/}/pre-migration-$(date +%Y%m%d-%H%M%S)-$$.dump"
chmod 600 "$temporary_file"
mv "$temporary_file" "$backup_file"
temporary_file=
if [ "${DEPLOY_BACKUP_PRUNE:-yes}" != no ]; then
  sh "$script_dir/prune-backups.sh" "$backup_dir" "${backup_file##*/}" >&2
fi
printf '%s\n' "$backup_file"

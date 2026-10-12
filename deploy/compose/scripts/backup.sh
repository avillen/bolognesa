#!/bin/sh
set -eu
. "$(dirname -- "$0")/common.sh"
require_runtime
backup_dir=${1:-${DEPLOY_BACKUP_DIR:-$DEPLOY_DIR/backups}}
umask 077
mkdir -p "$backup_dir"
wait_database
temporary_file=$(mktemp "${backup_dir%/}/.bolognesa-backup.XXXXXX")
trap 'rm -f "$temporary_file"' 0
compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$temporary_file"
test -s "$temporary_file"
compose exec -T db pg_restore --list < "$temporary_file" >/dev/null
backup_file="${backup_dir%/}/pre-migration-$(date +%Y%m%d-%H%M%S)-$$.dump"
chmod 600 "$temporary_file"
mv "$temporary_file" "$backup_file"
trap - 0
printf '%s\n' "$backup_file"

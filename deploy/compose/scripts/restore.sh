#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || { [ "$#" -eq 2 ] && [ "$2" != "--yes" ]; }; then
  printf 'Usage: %s BACKUP_FILE [--yes]\n' "$0" >&2
  exit 2
fi

backup_file=$1
confirm=no
if [ "$#" -eq 2 ]; then
  confirm=yes
fi
case "$backup_file" in
  /*) ;;
  *) backup_file="$PWD/$backup_file" ;;
esac
test -f "$backup_file" && test -s "$backup_file" || {
  printf 'Backup file is missing or empty: %s\n' "$backup_file" >&2
  exit 1
}

. "$(dirname -- "$0")/common.sh"
require_runtime

wait_database
compose exec -T db pg_restore --list < "$backup_file" >/dev/null

if [ "$confirm" != yes ]; then
  printf 'This replaces the current Bolognesa database. Type RESTORE to continue: '
  if ! IFS= read -r confirmation; then
    printf '\nRestore cancelled.\n' >&2
    exit 1
  fi
  if [ "$confirmation" != RESTORE ]; then
    printf 'Restore cancelled.\n' >&2
    exit 1
  fi
fi

compose stop app
compose exec -T db dropdb -U bolognesa --if-exists bolognesa
compose exec -T db createdb -U bolognesa -O bolognesa bolognesa
compose exec -T db pg_restore -U bolognesa -d bolognesa --no-owner < "$backup_file"
printf 'Database restored from %s. The app remains stopped; set BOLOGNESA_IMAGE to the matching release before starting it.\n' "$backup_file"

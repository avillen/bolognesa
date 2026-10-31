#!/bin/sh
set -eu
keep=${DEPLOY_BACKUP_KEEP:-3}
case "$keep" in
  ''|*[!0-9]*) echo 'DEPLOY_BACKUP_KEEP must be a positive integer' >&2; exit 2 ;;
esac
if ! [ "$keep" -gt 0 ] 2>/dev/null; then
  echo 'DEPLOY_BACKUP_KEEP must be a positive integer' >&2
  exit 2
fi
if [ "${1:-}" = --check ]; then exit 0; fi
dry_run=false
if [ "${1:-}" = --dry-run ]; then dry_run=true; shift; fi
backup_dir=${1:?Usage: prune-backups.sh [--dry-run] BACKUP_DIR [PROTECTED_FILENAME]}
protected=${2:-}
test -d "$backup_dir"
. "$(dirname -- "$0")/backup-lock.sh"
listing=
finish() {
  if [ -n "$listing" ]; then rm -f "$listing" "$listing.sorted"; fi
  backup_lock_release
}
trap finish 0
if [ "$dry_run" != true ]; then backup_lock_acquire "$backup_dir"; fi
managed_name() {
  printf '%s\n' "$1" | LC_ALL=C grep -Eq '^pre-migration-[0-9]{8}-[0-9]{6}(-[0-9]+)?\.dump$'
}
if [ -n "$protected" ]; then
  managed_name "$protected" && test -f "$backup_dir/$protected" &&
    test ! -L "$backup_dir/$protected" || {
      echo 'Protected backup must be a managed regular file in the backup directory' >&2
      exit 2
    }
fi
umask 077
listing=$(mktemp "${TMPDIR:-/tmp}/bolognesa-backup-retention.XXXXXX")
# common.sh disables globbing. Enumerate only this directory's managed dumps.
(
  set +f
  for backup in "$backup_dir"/pre-migration-*.dump; do
    test -f "$backup" && test ! -L "$backup" || continue
    name=${backup##*/}
    managed_name "$name" || continue
    # GNU/BusyBox stat on Linux; BSD stat on the operator's macOS machine.
    if modified=$(stat -c '%Y' "$backup" 2>/dev/null); then :
    else modified=$(stat -f '%m' "$backup"); fi
    priority=0
    if [ "$name" = "$protected" ]; then priority=1; fi
    printf '%s %s %s\n' "$priority" "$modified" "$name"
  done
) > "$listing"
LC_ALL=C sort -k1,1nr -k2,2nr -k3,3r "$listing" > "$listing.sorted"
count=0
while IFS=' ' read -r priority modified name; do
  count=$((count+1))
  if [ "$count" -le "$keep" ]; then continue; fi
  if [ "$dry_run" = true ]; then
    printf 'Would remove backup: %s\n' "$name"
  else
    rm -f -- "$backup_dir/$name" "$backup_dir/$name.image-ref"
    printf 'Removed backup: %s\n' "$name"
  fi
done < "$listing.sorted"

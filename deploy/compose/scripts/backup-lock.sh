# Shared by backup, update and retention. Child operations inherit the owner token.
backup_lock_owned=no
backup_lock_acquire() {
  backup_lock_dir="${1%/}/.bolognesa-backup.lock"
  if [ -n "${DEPLOY_BACKUP_LOCK_TOKEN:-}" ] &&
    [ "$(cat "$backup_lock_dir/owner" 2>/dev/null || true)" = "$DEPLOY_BACKUP_LOCK_TOKEN" ]; then
    return 0
  fi
  mkdir -p "$1"
  if ! (umask 077; mkdir "$backup_lock_dir") 2>/dev/null; then
    echo 'A backup, update or cleanup already holds the backup lock; retry after it finishes' >&2
    return 1
  fi
  backup_lock_owned=yes
  DEPLOY_BACKUP_LOCK_TOKEN=$$
  export DEPLOY_BACKUP_LOCK_TOKEN
  printf '%s\n' "$DEPLOY_BACKUP_LOCK_TOKEN" > "$backup_lock_dir/owner"
}
backup_lock_release() {
  if [ "$backup_lock_owned" = yes ]; then
    rm -f "$backup_lock_dir/owner"
    rmdir "$backup_lock_dir"
    backup_lock_owned=no
  fi
}

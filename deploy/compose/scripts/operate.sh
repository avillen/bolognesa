#!/bin/sh
set -eu
operation=${1:?Usage: operate.sh OPERATION [ARGUMENTS]}
shift
. "$(dirname -- "$0")/common.sh"
export DEPLOY_DIR DOCKER_BIN COMPOSE_FILE
case "$operation" in
  init)
    umask 077
    mkdir -p backups
    if [ ! -f .env ]; then
      test -f .env.example
      secret=$(openssl rand -hex 64); password=$(openssl rand -hex 32)
      sed -e "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$secret/" -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$password/" .env.example > .env.tmp
      chmod 600 .env.tmp; mv .env.tmp .env
    fi
    chmod 600 .env
    echo 'Environment ready; configure paths and host before installing'
    ;;
  preflight)
    require_runtime
    minimum_kib=${DEPLOY_MIN_FREE_KIB:-262144}
    case "$minimum_kib" in ''|*[!0-9]*) echo 'DEPLOY_MIN_FREE_KIB must be an integer' >&2; exit 2 ;; esac
    available_kib=$(df -Pk "$DEPLOY_DIR" | awk 'END {print $4}')
    test "$available_kib" -ge "$minimum_kib" || { echo 'Insufficient deployment storage for image/backup budget' >&2; exit 1; }
    "$DOCKER_BIN" version --format 'Docker {{.Server.Version}} {{.Server.Arch}}'
    command -v curl >/dev/null
    for key in MEDIA_PATH MOVIES_PATH SERIES_PATH POSTGRES_DATA_PATH; do
      source_path=$(runtime_value "$key")
      if [ -n "$source_path" ]; then
        test -d "$source_path" || { echo "Configured $key directory does not exist" >&2; exit 1; }
        # PostgreSQL owns its private data directory; the operator need not read it.
        if [ "$key" != POSTGRES_DATA_PATH ]; then
          test -r "$source_path" && test -x "$source_path" || { echo "Configured $key is not readable by the operator" >&2; exit 1; }
        fi
      fi
    done
    echo 'Deployment preflight passed'
    ;;
  install|update)
    DEPLOY_OPERATION=$operation; export DEPLOY_OPERATION
    exec "$script_dir/update.sh" "$@"
    ;;
  backup) exec "$script_dir/backup.sh" "$@" ;;
  restore) exec "$script_dir/restore.sh" "$@" ;;
  status) require_runtime; compose ps ;;
  media-up)
    require_runtime
    compose pull sonarr radarr prowlarr
    compose up -d --no-deps sonarr radarr prowlarr
    compose ps sonarr radarr prowlarr
    ;;
  media-status) require_runtime; compose ps sonarr radarr prowlarr ;;
  media-logs) require_runtime; compose logs --tail 100 --follow sonarr radarr prowlarr ;;
  media-stop) require_runtime; compose stop sonarr radarr prowlarr ;;
  logs) require_runtime; compose logs --tail 100 --follow app db ;;
  console) require_runtime; compose exec app /app/bin/bolognesa remote ;;
  psql) require_runtime; compose exec db psql -U bolognesa -d bolognesa ;;
  stop) require_runtime; compose stop app db ;;
  *) echo "Unknown operation: $operation" >&2; exit 2 ;;
esac

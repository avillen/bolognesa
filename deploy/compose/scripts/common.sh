#!/bin/sh
set -f
# Runtime .env is consumed by Compose, never executed as shell code.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_DIR=${DEPLOY_DIR:-$(CDPATH= cd -- "$script_dir/.." && pwd)}
DOCKER_BIN=${DOCKER_BIN:-docker}
COMPOSE_FILE=${COMPOSE_FILE:-compose.yaml}
cd "$DEPLOY_DIR"
compose() {
  compose_args=$COMPOSE_FILE
  set -- --env-file "$DEPLOY_DIR/.env" --project-directory "$DEPLOY_DIR" "$@"
  compose_prefix=
  old_ifs=$IFS; IFS=:
  for compose_path in $compose_args; do
    case "$compose_path" in /*) ;; *) compose_path="$DEPLOY_DIR/$compose_path" ;; esac
    test -f "$compose_path" || { echo "Missing Compose file: $compose_path" >&2; IFS=$old_ifs; return 1; }
    compose_prefix="$compose_path${compose_prefix:+:$compose_prefix}"
  done
  for compose_path in $compose_prefix; do set -- -f "$compose_path" "$@"; done
  IFS=$old_ifs
  "$DOCKER_BIN" compose "$@"
}
runtime_value() {
  compose config --environment | awk -v key="$1" 'index($0, key "=") == 1 {print substr($0, length(key)+2)}'
}
require_runtime() {
  test -f .env || { echo "Missing $DEPLOY_DIR/.env; configure the installation first" >&2; exit 1; }
  compose config --quiet
}
database_id() { compose ps -a -q db; }
wait_database() {
  existing_db=$(database_id)
  test -n "$existing_db" || { echo 'Database does not exist; refusing to create it for this operation' >&2; return 1; }
  "$DOCKER_BIN" start "$existing_db" >&2
  wait_count=0
  until [ "$("$DOCKER_BIN" inspect --format '{{.State.Health.Status}}' "$existing_db" 2>/dev/null || true)" = healthy ]; do
    wait_count=$((wait_count+1))
    if [ "$wait_count" -ge "${DEPLOY_WAIT_ATTEMPTS:-60}" ]; then
      echo 'PostgreSQL did not become healthy; inspect database logs' >&2
      return 1
    fi
    sleep "${DEPLOY_WAIT_INTERVAL:-2}"
  done
}
verify_http() {
  test -n "${DEPLOY_HEALTH_URL:-}" || { echo 'Set DEPLOY_HEALTH_URL' >&2; return 1; }
  http_attempt=0
  http_deadline=$(($(date +%s)+180))
  while :; do
    if http_status=$(curl --fail --location --max-redirs 2 --silent --show-error --connect-timeout 5 --max-time 15 --write-out '%{http_code}' "$DEPLOY_HEALTH_URL" -o /dev/null) && [ "$http_status" = 200 ]; then return 0; fi
    http_attempt=$((http_attempt+1))
    if [ "$http_attempt" -gt "${DEPLOY_HTTP_RETRIES:-20}" ] || [ "$(date +%s)" -ge "$http_deadline" ]; then
      echo 'Application HTTP verification failed' >&2; return 1
    fi
    sleep "${DEPLOY_WAIT_INTERVAL:-2}"
  done
}

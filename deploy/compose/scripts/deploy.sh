#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
source_dir=${DEPLOY_SOURCE_DIR:-$(cd "$script_dir/.." && pwd)}
operation=${1:?Usage: deploy.sh OPERATION [ARGUMENTS]}; shift
export DEPLOY_DIR=${DEPLOY_DIR:-$source_dir}
export DOCKER_BIN=${DOCKER_BIN:-docker}
export COMPOSE_FILE=${DEPLOY_COMPOSE_FILES:-${COMPOSE_FILE:-compose.yaml}}
export DEPLOY_HEALTH_URL=${DEPLOY_HEALTH_URL:-http://127.0.0.1:4000/}
transport=${DEPLOY_TRANSPORT:-local}
case "$transport" in local|ssh) ;; *) echo 'DEPLOY_TRANSPORT must be local or ssh' >&2; exit 2 ;; esac
if [[ $transport == ssh ]]; then
  [[ -n ${DEPLOY_HOST:-} && $DEPLOY_HOST != -* ]] || { echo 'Set DEPLOY_HOST to an SSH destination' >&2; exit 2; }
fi
quote() {
  local value=${1//\'/\'\\\'\'}
  printf "'%s'" "$value"
}
remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$DEPLOY_HOST" "$1"; }
upload() {
  local stage path name mapped=
  stage=$(mktemp -d)
  trap 'rm -rf "$stage"' EXIT
  cp -R "$source_dir/scripts" "$stage/scripts"
  cp "$source_dir/.env.example" "$stage/.env.example"
  local paths=(); IFS=: read -r -a paths <<< "$COMPOSE_FILE"
  for path in "${paths[@]}"; do
    case "$path" in /*) ;; *) path="$source_dir/$path" ;; esac
    name=$(basename "$path")
    [[ ! -e $stage/$name ]] || { echo "Duplicate Compose basename: $name" >&2; exit 2; }
    cp "$path" "$stage/$name"
    mapped+="${mapped:+:}$name"
  done
  if [[ $transport == local ]]; then
    mkdir -p "$DEPLOY_DIR"
    tar -C "$stage" -cf - . | tar -C "$DEPLOY_DIR" -xf -
  else
    local command
    command="mkdir -p $(quote "$DEPLOY_DIR") && tar -C $(quote "$DEPLOY_DIR") -xf -"
    tar -C "$stage" -cf - . | remote "$command"
  fi
  if [[ -n ${DEPLOY_IMAGE_TAR:-} ]]; then
    if [[ $transport == local ]]; then cp "$DEPLOY_IMAGE_TAR" "$DEPLOY_DIR/image.tar"; "$DOCKER_BIN" load -i "$DEPLOY_DIR/image.tar";
    else
      scp -O -o BatchMode=yes "$DEPLOY_IMAGE_TAR" "$DEPLOY_HOST:$(quote "$DEPLOY_DIR/image.tar")"
      remote "$(quote "$DOCKER_BIN") load -i $(quote "$DEPLOY_DIR/image.tar")"
    fi
  fi
  export COMPOSE_FILE=$mapped
  rm -rf "$stage"; trap - EXIT
}
case "$operation" in
  build)
    image=${DEPLOY_IMAGE_NAME:-bolognesa:lan}
    image_tar=${DEPLOY_IMAGE_TAR:-/tmp/bolognesa-image.tar}
    args=(buildx build --build-arg BOLOGNESA_LAN_HTTP=true --load -t "$image")
    if [[ -n ${DEPLOY_BUILD_PLATFORM:-} ]]; then args+=(--platform "$DEPLOY_BUILD_PLATFORM"); fi
    "${BUILD_DOCKER_BIN:-docker}" "${args[@]}" "$(cd "$script_dir/../../.." && pwd)"
    "${BUILD_DOCKER_BIN:-docker}" save -o "$image_tar" "$image"
    printf 'Exported %s to %s\n' "$image" "$image_tar"
    exit ;;
  upload) upload; exit ;;
  init) upload ;;
esac
# Preserve order but map locally selected filenames to their installed basenames.
paths=(); IFS=: read -r -a paths <<< "$COMPOSE_FILE"
installed_files=
for path in "${paths[@]}"; do installed_files+="${installed_files:+:}$(basename "$path")"; done
export COMPOSE_FILE=$installed_files
if [[ $transport == local ]]; then
  exec sh "$DEPLOY_DIR/scripts/operate.sh" "$operation" "$@"
fi
command=env
for key in DEPLOY_DIR DOCKER_BIN COMPOSE_FILE DEPLOY_HEALTH_URL DEPLOY_BACKUP_DIR ALLOW_DATABASE_CONFIG_CHANGE EXPECTED_DATABASE_SOURCE DEPLOY_HTTP_RETRIES DEPLOY_WAIT_ATTEMPTS DEPLOY_WAIT_INTERVAL; do
  if [[ -n ${!key:-} ]]; then command+=" $(quote "$key=${!key}")"; fi
done
command+=" sh $(quote "$DEPLOY_DIR/scripts/operate.sh") $(quote "$operation")"
for argument in "$@"; do command+=" $(quote "$argument")"; done
case "$operation" in
  console|psql|restore) exec ssh -tt -o BatchMode=yes -o ConnectTimeout=10 "$DEPLOY_HOST" "$command" ;;
  *) remote "$command" ;;
esac

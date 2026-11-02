#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
worktree=$(git rev-parse --show-toplevel)
checksum=$(printf '%s' "$worktree" | cksum | awk '{print $1}')
project="bolognesa-dev-$checksum"
BOLOGNESA_DEV_PORT=$((20000 + checksum % 30000))
BOLOGNESA_GIT_COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir)
export BOLOGNESA_GIT_COMMON_DIR BOLOGNESA_DEV_PORT

# Refuse to control a project whose app is bound to another checkout.
container=$(docker ps -aq --filter "label=com.docker.compose.project=$project" --filter 'label=com.docker.compose.service=app' | head -n 1)
if [ -n "$container" ]; then
  mounted=$(docker inspect "$container" -f '{{range .Mounts}}{{if eq .Destination "/app"}}{{.Source}}{{end}}{{end}}')
else
  container=$(docker ps -aq --filter "label=com.docker.compose.project=$project" --filter 'label=com.docker.compose.service=db' | head -n 1)
  mounted=$worktree
  if [ -n "$container" ]; then
    mounted=$(docker inspect "$container" -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}')
  fi
fi
if [ -n "$container" ]; then
  actual=$(cd "$mounted" 2>/dev/null && pwd -P) || actual=$mounted
  expected=$(cd "$worktree" 2>/dev/null && pwd -P) || expected=$worktree
  if [ "$actual" != "$expected" ]; then
    echo "Compose project $project belongs to another checkout: $mounted" >&2
    exit 1
  fi
fi
exec docker compose -p "$project" -f compose.dev.yaml "$@"

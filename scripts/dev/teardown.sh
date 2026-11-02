#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
worktree=$(git rev-parse --show-toplevel)
common=$(git rev-parse --path-format=absolute --git-common-dir)
primary=$(cd "$(dirname "$common")" && pwd -P)
current=$(cd "$worktree" && pwd -P)
if [ "$current" = "$primary" ]; then
  echo "Refusing to remove the primary checkout's development data." >&2
  exit 1
fi

checksum=$(printf '%s' "$worktree" | cksum | awk '{print $1}')
project="bolognesa-dev-$checksum"
lock="${TMPDIR:-/tmp}/bolognesa-dev-$checksum.lock"
i=0
until mkdir "$lock" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    echo "Timed out waiting for development startup: $lock" >&2
    exit 1
  fi
  sleep 2
done
trap 'rmdir "$lock"' EXIT
trap 'exit 1' HUP INT TERM

# Unlabelled volumes need a matching container or the owner record written by
# ensure.sh; compose.sh validates any remaining container's checkout path.
if docker volume inspect "${project}_database" >/dev/null 2>&1; then
  owner=$(docker volume inspect "${project}_database" -f '{{index .Labels "bolognesa.worktree"}}')
  if [ -n "$owner" ] && [ "$owner" != '<no value>' ]; then
    actual=$(cd "$owner" 2>/dev/null && pwd -P) || actual=$owner
    if [ "$actual" != "$current" ]; then
      echo "Refusing to remove another checkout's database: $owner" >&2
      exit 1
    fi
  elif [ -z "$(docker ps -aq --filter "label=com.docker.compose.project=$project" | head -n 1)" ]; then
    owner_file=$(git rev-parse --git-path bolognesa-compose-owner)
    if [ ! -f "$owner_file" ] || [ "$(cat "$owner_file")" != "$current" ]; then
      echo "Cannot establish ownership of the existing database volume for $project." >&2
      exit 1
    fi
  fi
fi

image="${project}-app"
if docker image inspect "$image" >/dev/null 2>&1; then
  image_project=$(docker image inspect "$image" -f '{{index .Config.Labels "com.docker.compose.project"}}')
  image_service=$(docker image inspect "$image" -f '{{index .Config.Labels "com.docker.compose.service"}}')
  if [ "$image_project" != "$project" ] || [ "$image_service" != app ]; then
    echo "Refusing to remove an image not owned by $project: $image" >&2
    exit 1
  fi
fi
sh scripts/dev/compose.sh down --volumes --remove-orphans
if docker image inspect "$image" >/dev/null 2>&1; then
  docker image rm "$image"
fi

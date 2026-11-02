#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
worktree=$(git rev-parse --show-toplevel)
checksum=$(printf '%s' "$worktree" | cksum | awk '{print $1}')
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

[ -n "${MEDIA_PATH:-}" ] || mkdir -p media
sh scripts/dev/compose.sh up -d
container=$(sh scripts/dev/compose.sh ps -q app)
if [ -z "$container" ]; then
  echo "Development app did not start." >&2
  exit 1
fi
# The worktree-specific Git metadata survives `compose down` and records which
# checkout created its volumes, even if no containers remain during removal.
owner_file=$(git rev-parse --git-path bolognesa-compose-owner)
(cd "$worktree" && pwd -P) > "$owner_file"
i=0
until sh scripts/dev/compose.sh exec -T app sh -c 'curl -fsS -o /dev/null -X POST -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"readiness\",\"version\":\"1\"}}}" http://127.0.0.1:4000/tidewave/mcp' 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    echo "Tidewave did not become ready; inspect Compose logs." >&2
    exit 1
  fi
  sleep 2
done

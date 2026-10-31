#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

mode="${1:-generate}"
if [[ "$mode" != "generate" && "$mode" != "--check" && "$mode" != "--verify-fullscreen" ]]; then
  echo "Usage: $0 [--check|--verify-fullscreen]" >&2
  exit 2
fi

temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
work_dir="$(mktemp -d "$temporary_root/bolognesa-screenshots.XXXXXX")"
container_name="bolognesa-screenshots-$$"
server_pid=""
container_started="false"
browser_container="bolognesa-screenshot-browser-$$"
browser_started="false"
completed="false"

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ "$browser_started" == "true" ]]; then
    docker stop "$browser_container" >/dev/null 2>&1 || true
  fi
  if [[ "$container_started" == "true" ]]; then
    docker stop "$container_name" >/dev/null 2>&1 || true
  fi
  if [[ "$completed" == "true" ]]; then
    rm -rf "$work_dir"
  else
    echo "Screenshot run logs retained in $work_dir." >&2
    if [[ -f "$work_dir/phoenix.log" ]]; then
      cat "$work_dir/phoenix.log" >&2
    fi
  fi
}
trap cleanup EXIT

if [[ ! -d node_modules/playwright ]]; then
  npm ci
fi
# Keep Chromium, native controls, fonts and rasterization identical on macOS and CI.
browser_image="mcr.microsoft.com/playwright:v1.55.1-noble@sha256:d8e0bdf35da90942fc8f97a65fa7f1969200ccd916ec0fd78780d80d9b81e07b"
docker run --detach --rm --init --ipc=host --platform linux/amd64 \
  --name "$browser_container" --publish 127.0.0.1::3000 \
  --volume "$repo_root/node_modules:/work/node_modules:ro" --workdir /work \
  "$browser_image" node node_modules/playwright/cli.js run-server \
  --host 0.0.0.0 --port 3000 >/dev/null
browser_started="true"
browser_port="$(docker port "$browser_container" 3000/tcp | awk -F: '{print $NF}')"
export BOLOGNESA_SCREENSHOT_BROWSER_WS="ws://127.0.0.1:$browser_port"
for _ in $(seq 1 40); do
  if curl --silent --fail "http://127.0.0.1:$browser_port/" >/dev/null; then
    break
  fi
  sleep 1
done
curl --silent --fail "http://127.0.0.1:$browser_port/" >/dev/null

output_dir="$repo_root/docs/screenshots"
if [[ "$mode" == "--check" ]]; then
  output_dir="$work_dir/output"
  mkdir -p "$output_dir"
fi
library_root="$work_dir/library"
mkdir -p "$library_root"
video_path="$work_dir/after-the-signal.webm"
ids_path="$work_dir/ids.json"

node scripts/screenshots/generate-demo-video.mjs "$video_path"

docker run --detach --rm \
  --name "$container_name" \
  --env POSTGRES_USER=postgres \
  --env POSTGRES_PASSWORD=postgres \
  --env POSTGRES_DB=bolognesa_screenshots \
  --publish 127.0.0.1::5432 \
  postgres:17 >/dev/null
container_started="true"
db_port="$(docker port "$container_name" 5432/tcp | awk -F: '{print $NF}')"

# The initialization server accepts only Unix sockets; wait for the final TCP listener.
for _ in $(seq 1 40); do
  if docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres -d bolognesa_screenshots >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker exec "$container_name" pg_isready -h 127.0.0.1 -U postgres -d bolognesa_screenshots >/dev/null

export MIX_ENV=screenshots
export BOLOGNESA_SCREENSHOT_DB_PORT="$db_port"
export BOLOGNESA_LIBRARY_ROOTS="$library_root"
export BOLOGNESA_SCREENSHOT_VIDEO="$video_path"
export BOLOGNESA_SCREENSHOT_IDS="$ids_path"

mix ecto.create
mix ecto.migrate --quiet
mix assets.deploy

start_server() {
  local app_port
  app_port="$(python3 -c 'import socket; sock = socket.socket(); sock.bind(("127.0.0.1", 0)); print(sock.getsockname()[1]); sock.close()')"
  PORT="$app_port" mix phx.server >"$work_dir/phoenix.log" 2>&1 &
  server_pid="$!"
  export BOLOGNESA_URL="http://127.0.0.1:$app_port"

  for _ in $(seq 1 40); do
    if curl --silent --fail "$BOLOGNESA_URL/login" >/dev/null; then
      return
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat "$work_dir/phoenix.log" >&2
      exit 1
    fi
    sleep 1
  done

  cat "$work_dir/phoenix.log" >&2
  echo "Phoenix did not start at $BOLOGNESA_URL." >&2
  exit 1
}

run_capture() {
  BOLOGNESA_SCREENSHOT_OUTPUT_DIR="$output_dir" \
    BOLOGNESA_CAPTURE_PHASE="$1" \
    npm run capture-screenshots
}

if [[ "$mode" == "--verify-fullscreen" ]]; then
  export BOLOGNESA_VERIFY_EPISODE_FULLSCREEN=1
else
  start_server
  run_capture public
  kill "$server_pid"
  wait "$server_pid" 2>/dev/null || true
  server_pid=""
fi

PORT=0 mix run scripts/screenshots/seed_readme_screenshots.exs

start_server
if [[ "$mode" == "--verify-fullscreen" ]]; then
  node scripts/playback/verify-episode-fullscreen.mjs
else
  run_capture app
fi

if [[ "$mode" == "--check" ]]; then
  python3 -B -m unittest discover -s test/scripts -p 'test_readme_screenshot_check.py'
  if ! python3 scripts/screenshots/compare-readme-screenshots.py "$repo_root/docs/screenshots" "$output_dir"; then
    echo "README screenshots are out of date. Run 'make screenshots' and commit the updated images." >&2
    exit 1
  fi
  echo "README screenshots are up to date."
fi

completed="true"

#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."
worktree=$(git rev-parse --show-toplevel)
checksum=$(printf '%s' "$worktree" | cksum | awk '{print $1}')
PORT=$((20000 + checksum % 30000))
BOLOGNESA_DB_NAME="bolognesa_dev_$checksum"
BOLOGNESA_TEST_DB_NAME="bolognesa_test_$checksum"
BOLOGNESA_TRANSCODE_ROOT=${BOLOGNESA_TRANSCODE_ROOT:-${TMPDIR:-/tmp}/bolognesa-transcode-$checksum}
BOLOGNESA_LIBRARY_ROOTS=${BOLOGNESA_LIBRARY_ROOTS:-${TMPDIR:-/tmp}/bolognesa-library-$checksum}
export PORT BOLOGNESA_DB_NAME BOLOGNESA_TEST_DB_NAME BOLOGNESA_TRANSCODE_ROOT BOLOGNESA_LIBRARY_ROOTS

case "${1:-}" in
  info)
    printf 'URL: http://localhost:%s\nDevelopment database: %s\nTest database: %s\n' \
      "$PORT" "$BOLOGNESA_DB_NAME" "$BOLOGNESA_TEST_DB_NAME"
    ;;
  setup) exec mix setup ;;
  server) exec mix phx.server ;;
  test) exec mix precommit ;;
  mcp)
    if [ ! -f _build/dev/lib/tidewave/ebin/Elixir.Mix.Tasks.Tidewave.Proxy.beam ]; then
      echo 'Run sh scripts/dev/local.sh setup before starting the Tidewave proxy.' >&2
      exit 1
    fi
    exec mix run --no-compile --no-start -e 'Mix.Tasks.Tidewave.Proxy.run([])'
    ;;
  *) echo 'Usage: sh scripts/dev/local.sh {info|setup|server|test|mcp}' >&2; exit 2 ;;
esac

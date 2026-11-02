#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."

# MCP uses stdout as its protocol channel. Startup messages belong on stderr.
sh scripts/dev/ensure.sh </dev/null >&2

exec sh scripts/dev/compose.sh exec -T app mix tidewave.proxy

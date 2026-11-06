#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."

# The proxy does not start Phoenix. Its tools target the port from local.sh info.
exec sh scripts/dev/local.sh mcp

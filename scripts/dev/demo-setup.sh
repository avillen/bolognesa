#!/bin/sh
set -eu

# The caller selects a dedicated database and media root for this worktree.
case "${BOLOGNESA_DB_NAME:-}" in bolognesa_demo_[0-9]*) ;; *) echo 'Use local.sh demo-setup.' >&2; exit 1 ;; esac
: "${BOLOGNESA_LIBRARY_ROOTS:?Missing demo media root}"
: "${BOLOGNESA_DEMO_EMAIL:?Set BOLOGNESA_DEMO_EMAIL to the demo login email}"
: "${BOLOGNESA_DEMO_PASSWORD:?Set BOLOGNESA_DEMO_PASSWORD to a demo password (12–72 characters)}"

command -v ffmpeg >/dev/null
mix setup
mix run scripts/dev/seed-demo.exs

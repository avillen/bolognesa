#!/bin/sh
set -eu

# The caller selects a dedicated database and media root for this worktree.
case "${BOLOGNESA_DB_NAME:-}" in bolognesa_demo_[0-9]*) ;; *) echo 'Use local.sh demo-setup.' >&2; exit 1 ;; esac
: "${BOLOGNESA_LIBRARY_ROOTS:?Missing demo media root}"
BOLOGNESA_DEMO_EMAIL=${BOLOGNESA_DEMO_EMAIL:-admin@example.com}
BOLOGNESA_DEMO_PASSWORD=${BOLOGNESA_DEMO_PASSWORD:-123456}
export BOLOGNESA_DEMO_EMAIL BOLOGNESA_DEMO_PASSWORD

command -v ffmpeg >/dev/null
mix setup
mix run scripts/dev/seed-demo.exs
mix run scripts/dev/seed-demo-music.exs

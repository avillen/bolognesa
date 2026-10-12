#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
target="$test_dir/install with ' quote"
mkdir -p "$target/scripts" "$test_dir/bin"
cat > "$target/scripts/operate.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$DEPLOY_DIR" "$DOCKER_BIN" "$COMPOSE_FILE" "$DEPLOY_HEALTH_URL" "$@" > "$TRACE"
SH
cat > "$test_dir/bin/ssh" <<'SH'
#!/bin/sh
# Run the quoted command through the same POSIX interpreter as the server.
while [ "${1:-}" = -o ] || [ "${1:-}" = -tt ]; do
  if [ "$1" = -tt ]; then shift; else shift 2; fi
done
shift
exec sh -c "$1"
SH
chmod +x "$test_dir/bin/ssh"
export DEPLOY_DIR="$target" DOCKER_BIN="$test_dir/docker with space" COMPOSE_FILE="first.yaml:second with space.yaml"
export DEPLOY_HEALTH_URL='http://private:4000/' PATH="$test_dir/bin:$PATH" TRACE="$test_dir/trace"
DEPLOY_TRANSPORT=local bash "$repo_dir/deploy/compose/scripts/deploy.sh" status "argument with ' quote"
cp "$TRACE" "$test_dir/local"
DEPLOY_TRANSPORT=ssh DEPLOY_HOST=user@example bash "$repo_dir/deploy/compose/scripts/deploy.sh" status "argument with ' quote"
cmp "$TRACE" "$test_dir/local"
grep -qx "argument with ' quote" "$TRACE"
export COMPOSE_FILE='first "quoted name".yaml:second with space.yaml'
export DEPLOY_TRANSPORT=local
bash "$repo_dir/deploy/compose/scripts/deploy.sh" status
cp "$TRACE" "$test_dir/direct"
make -s -C "$repo_dir" deploy-status DEPLOY_CONFIG=/dev/null DEPLOY_TRANSPORT=local DEPLOY_DIR="$DEPLOY_DIR" DOCKER_BIN="$DOCKER_BIN" DEPLOY_COMPOSE_FILES="$COMPOSE_FILE" DEPLOY_HEALTH_URL="$DEPLOY_HEALTH_URL"
cmp "$TRACE" "$test_dir/direct"
echo 'Local/SSH and Make transport quoting passed'

#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

cat > "$test_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == api ]]; then
  if [[ $2 == */actions/workflows/* ]]; then printf '%s\n' '.github/workflows/container-image.yml';
  else printf '%s\n' "${MOCK_WORKFLOW_PATH:-.github/workflows/container-image.yml}"; fi
  exit
fi
case "$1 $2" in
  'run list') printf '%s\n' "${MOCK_RUN_IDS:-123}" ;;
  'run watch') [[ ${MOCK_CI_FAILED:-0} == 0 ]] ;;
  'run view') printf '%s main completed success\n' "$COMMIT_SHA" ;;
  'run download')
    while (( $# )); do
      if [[ $1 == --dir ]]; then
        shift
        printf 'variant=lan\ncommit=%s\nimage=ghcr.io/avillen/bolognesa@%s\n' \
          "${MOCK_ARTIFACT_SHA:-$COMMIT_SHA}" "$MOCK_DIGEST" > "$1/image-ref.txt"
        exit 0
      fi
      shift
    done
    exit 1
    ;;
  *) exit 1 ;;
esac
EOF

cat > "$test_dir/bin/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_MAKE_LOG"
EOF
chmod +x "$test_dir/bin/gh" "$test_dir/bin/make"

export PATH="$test_dir/bin:$PATH" COMMIT_SHA="$sha" MOCK_DIGEST="$digest" IMAGE_REPOSITORY=ghcr.io/avillen/bolognesa
export MOCK_MAKE_LOG="$test_dir/make.log"

bash "$repo_dir/deploy/compose/scripts/release.sh"
grep -qx "deploy-update IMAGE_REF=ghcr.io/avillen/bolognesa@$digest" "$MOCK_MAKE_LOG"

: > "$MOCK_MAKE_LOG"
export MOCK_ARTIFACT_SHA=cccccccccccccccccccccccccccccccccccccccc
if bash "$repo_dir/deploy/compose/scripts/release.sh" > "$test_dir/rejected.log" 2>&1; then
  echo 'Mismatched artifact SHA was accepted' >&2
  exit 1
fi
test ! -s "$MOCK_MAKE_LOG"
unset MOCK_ARTIFACT_SHA

export MOCK_RUN_IDS=$'123\n456'
if bash "$repo_dir/deploy/compose/scripts/release.sh" > "$test_dir/rejected.log" 2>&1; then
  echo 'Ambiguous CI runs were accepted' >&2
  exit 1
fi
test ! -s "$MOCK_MAKE_LOG"
unset MOCK_RUN_IDS

export MOCK_CI_FAILED=1
if bash "$repo_dir/deploy/compose/scripts/release.sh" > "$test_dir/rejected.log" 2>&1; then
  echo 'Failed CI run was accepted' >&2
  exit 1
fi
test ! -s "$MOCK_MAKE_LOG"

unset MOCK_CI_FAILED
export MOCK_RUN_IDS=$'123\n456' DEPLOY_RUN_ID=123
bash "$repo_dir/deploy/compose/scripts/release.sh"
test -s "$MOCK_MAKE_LOG"
unset MOCK_RUN_IDS DEPLOY_RUN_ID
: > "$MOCK_MAKE_LOG"
export MOCK_WORKFLOW_PATH=.github/workflows/other.yml
if bash "$repo_dir/deploy/compose/scripts/release.sh" > "$test_dir/rejected.log" 2>&1; then
  echo 'Unrelated workflow was accepted' >&2; exit 1
fi
test ! -s "$MOCK_MAKE_LOG"
echo 'Compose release validation passed'

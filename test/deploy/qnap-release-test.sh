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
case "$1 $2" in
  'run list') printf '%s\n' "${MOCK_RUN_IDS:-123}" ;;
  'run watch') [[ ${MOCK_CI_FAILED:-0} == 0 ]] ;;
  'run view') printf '%s main completed success\n' "$COMMIT_SHA" ;;
  'run download')
    while (( $# )); do
      if [[ $1 == --dir ]]; then
        shift
        printf 'commit=%s\nimage=ghcr.io/avillen/bolognesa-lan@%s\n' \
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

export PATH="$test_dir/bin:$PATH" COMMIT_SHA="$sha" MOCK_DIGEST="$digest"
export MOCK_MAKE_LOG="$test_dir/make.log"

bash "$repo_dir/deploy/qnap/scripts/release.sh"
grep -qx "qnap-update-image IMAGE_REF=ghcr.io/avillen/bolognesa-lan@$digest" "$MOCK_MAKE_LOG"

: > "$MOCK_MAKE_LOG"
export MOCK_ARTIFACT_SHA=cccccccccccccccccccccccccccccccccccccccc
if bash "$repo_dir/deploy/qnap/scripts/release.sh" > "$test_dir/rejected.log" 2>&1; then
  echo 'Mismatched artifact SHA was accepted' >&2
  exit 1
fi
test ! -s "$MOCK_MAKE_LOG"
unset MOCK_ARTIFACT_SHA

export MOCK_RUN_IDS=$'123\n456'
if bash "$repo_dir/deploy/qnap/scripts/release.sh" > "$test_dir/rejected.log" 2>&1; then
  echo 'Ambiguous CI runs were accepted' >&2
  exit 1
fi
test ! -s "$MOCK_MAKE_LOG"
unset MOCK_RUN_IDS

export MOCK_CI_FAILED=1
if bash "$repo_dir/deploy/qnap/scripts/release.sh" > "$test_dir/rejected.log" 2>&1; then
  echo 'Failed CI run was accepted' >&2
  exit 1
fi
test ! -s "$MOCK_MAKE_LOG"

echo 'qnap release script tests passed'

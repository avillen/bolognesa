#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo_dir"
commit_sha=${COMMIT_SHA:-$(git rev-parse HEAD)}
[[ $commit_sha =~ ^[0-9a-f]{40}$ ]] || { echo 'COMMIT_SHA must be a full lowercase Git SHA' >&2; exit 2; }
repository=${IMAGE_REPOSITORY:-}
if [[ -z $repository ]]; then
  owner_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  repository="ghcr.io/$(printf '%s' "$owner_repo" | tr '[:upper:]' '[:lower:]')"
fi
workflow=${DEPLOY_WORKFLOW:-container-image.yml}
run_id=${DEPLOY_RUN_ID:-}
if [[ -z $run_id ]]; then
  run_id=$(gh run list --workflow "$workflow" --branch main --commit "$commit_sha" --limit 100 \
    --json databaseId,headSha,headBranch --jq ".[] | select(.headSha == \"$commit_sha\" and .headBranch == \"main\") | .databaseId")
fi
[[ $run_id =~ ^[0-9]+$ ]] || { echo 'Expected exactly one main image run; select DEPLOY_RUN_ID explicitly for repeated CI runs' >&2; exit 1; }
gh run watch "$run_id" --compact --exit-status
run_state=$(gh run view "$run_id" --json headSha,headBranch,status,conclusion --jq '.headSha + " " + .headBranch + " " + .status + " " + .conclusion')
[[ $run_state == "$commit_sha main completed success" ]] || { echo 'Run is not a successful main build of the requested SHA' >&2; exit 1; }
workflow_path=$(gh api "repos/{owner}/{repo}/actions/workflows/$workflow" --jq .path)
run_path=$(gh api "repos/{owner}/{repo}/actions/runs/$run_id" --jq .path)
[[ -n $workflow_path && $workflow_path == "$run_path" ]] || { echo 'Selected run belongs to a different workflow' >&2; exit 1; }
artifact_dir=$(mktemp -d)
trap 'rm -rf "$artifact_dir"' EXIT
gh run download "$run_id" --name "${DEPLOY_ARTIFACT:-server-image-ref}" --dir "$artifact_dir"
file=$artifact_dir/image-ref.txt
[[ -f $file && $(wc -l < "$file") -eq 3 ]] || { echo 'Missing or malformed release artifact' >&2; exit 1; }
variant=$(sed -n '1s/^variant=//p' "$file")
artifact_sha=$(sed -n '2s/^commit=//p' "$file")
image=$(sed -n '3s/^image=//p' "$file")
[[ $variant == lan && $artifact_sha == "$commit_sha" && $image == "$repository@sha256:"* ]] || { echo 'Artifact variant, SHA or image repository differs from the requested release' >&2; exit 1; }
digest=${image#"$repository@sha256:"}
[[ $digest =~ ^[0-9a-f]{64}$ ]] || { echo 'Invalid image digest' >&2; exit 1; }
make deploy-update "IMAGE_REF=$image"
printf 'Verified release %s from run %s as %s\n' "$commit_sha" "$run_id" "$image"

# Commit conventions

Commits are the durable public record of how the project changes. Keep each commit focused, explain its intent, and review both the staged patch and its metadata before creating it.

## Messages

Use a short, imperative subject in this form:

```text
type(scope): summary
```

Use a lowercase type such as `feat`, `fix`, `docs`, `test`, `refactor`, `build`, or `ci`. The scope is optional; use a small area such as `catalog` or `playback` when it helps. Keep the summary specific and concise. Add a body only when it explains context or a trade-off that is not clear from the patch. Do not put personal, deployment, or secret values in subjects, bodies, branch names, or trailers.

Examples:

```text
feat(catalog): preserve manual identification corrections
fix(playback): report unsupported media formats
docs: clarify local Docker setup
```

## Privacy checks

Before committing, inspect the staged changes and check that they contain no credentials, tokens, private keys, personal contact details, private media names, home or deployment paths, internal addresses, or operational details. Use generic placeholders in examples. Check filenames, commit messages, and metadata as well as file contents. Never stage local environment files, private logs, database dumps, or media.

Before pushing, scan the commits being introduced with Gitleaks. CI scans the same incoming commit range for pushes and pull requests, using a full Git checkout so the range can be compared reliably. This automated scan catches known secret patterns; it cannot recognize every kind of private information, so human review remains required. Review the full history separately before the first public release. Do not add blanket allowlist entries to make a finding pass without verifying that the value is safe and documenting why it is a false positive.

The root `.gitleaksignore` contains only exact fingerprints for the fixed development and test `secret_key_base` values. These values are not used by production configuration. Reassess and remove the exceptions if those source lines or their history change; do not add path-wide or rule-wide exclusions.

If a secret is committed, treat it as exposed: revoke or rotate it first, notify the maintainer privately, then coordinate history cleanup. Deleting it in a later commit does not remove it from earlier commits or existing clones, forks, caches, or artifacts. Do not publish the affected history until the maintainer has reviewed the cleanup.

## Local scan

Run the same pinned Gitleaks image used by CI from the repository root, replacing `origin/main` with the branch you will merge into when needed:

```sh
docker run --rm --volume "$PWD:/repo" --workdir /repo ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:b109bc5f8f76a38196a3e413704fc5b9e3c32360bce4e4b603bd6f45b3721dbb git --redact --log-opts="origin/main..HEAD"
```

For a full-history audit before release, omit `--log-opts`. That audit may report legacy findings even when the current files are clean. Review findings without copying values into issues or pull requests; false positives must be assessed by the maintainer.

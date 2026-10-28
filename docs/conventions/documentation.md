# Documentation conventions

The repository's documentation is part of the public project interface. Keep it concise, accurate, in English, and understandable without private deployment details or prior conversations. Prefer short explanations and direct steps; put technical detail in the relevant guide instead of repeating it in the README.

## What belongs in `docs/`

- `README.md` at the repository root: project introduction and local setup.
- `CONTRIBUTING.md`: contribution workflow and checks.
- `CHANGELOG.md`: release notes and version-specific upgrade information; keep the README independent of application release versions. Internal changes before the first announcement do not need user migration instructions.
- `docs/product.md`: audience, scope, and product principles.
- `docs/status.md`: a short snapshot of implemented behavior, evidence limits, and release blockers.
- `docs/roadmap.md`: product outcomes and open questions, without duplicating status details.
- `docs/conventions/`: current, durable rules. Update the relevant convention when an agreed rule changes.
- `docs/decisions/`: durable architectural decisions, rationale, consequences, and replacement links.

Temporary designs and execution plans belong in the change that uses them. Remove completed working notes or distill any lasting rule into a convention or decision. Do not keep deployment diaries, personal inventories, or redundant milestone histories in the public documentation.

## Privacy and evidence

- Use generic paths, addresses, usernames, and sample values. Never include credentials, private media names, personal library inventories, or identifying operational details.
- Describe a result only at the level that helps a contributor understand behavior or limits. Keep private deployment evidence outside the repository unless it has clear public value and has been sanitized.
- Distinguish automated tests, local checks, deployment observations, and device testing. Do not infer one from another.
- Before the first public release, review the tracked tree and Git history for sensitive values. Editing a file does not remove its earlier versions from Git history.

## Maintenance

- Use descriptive filenames and relative links. Keep an index for collections of decision records.
- Prefer editing the current document over appending a dated log. Add a decision record only for a meaningful boundary, public contract, dependency, or organizational choice.
- Remove links when their targets are removed; check all Markdown links after reorganizing documentation.
- Do not add tool-specific documentation directories. Tool workflows must follow the repository's document structure.
- Document only behavior that exists or a clearly labeled open question. Avoid duplicating instructions from the root README or contributor guide.

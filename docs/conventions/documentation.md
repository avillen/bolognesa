# Documentation conventions

The repository's documentation is part of the public project interface. Keep it concise, accurate, in English, and understandable without private deployment details or prior conversations. Prefer short explanations and direct steps; put technical detail in the relevant guide instead of repeating it in the README.

## Where documentation belongs

- `README.md` at the repository root: project introduction, user capabilities, and quick start.
- `CONTRIBUTING.md`: development setup, contribution workflow, and checks.
- `CHANGELOG.md`: release notes and version-specific upgrade information; keep the README independent of application release versions. Internal changes before the first announcement do not need user migration instructions.
- `docs/conventions/`: current, durable rules, with one owner per topic in the [conventions index](README.md). Link to the owner instead of repeating a rule; update it when an agreed rule changes.
- `docs/decisions/`: durable architectural decisions, rationale, consequences, and replacement links.
- `docs/`: focused guides, including playback limits and verification procedures.
- `deploy/compose/`: installation, backup, recovery, and monitoring procedures.

Track tasks, verification gaps, and blockers in GitHub issues; track release scope and acceptance criteria in milestones. Record verification evidence in the relevant issue or pull request. Keep user-facing capabilities and limitations in the README or relevant guide.

Temporary designs and execution plans belong in the change that uses them. Remove completed working notes or distill any lasting rule into a convention or decision. Do not keep deployment diaries, personal inventories, or redundant milestone histories in the public documentation.

## Release notes

Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/): retain an `Unreleased` section, use `## [VERSION] - YYYY-MM-DD` headings with the publication date, and group changes under the applicable `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, or `Security` categories. Put an optional release description below the heading. Keep `Limitations` and `Upgrading` sections when needed, and link version headings to release comparisons (or the first release). Confirm the planned date when publishing a prepared release.

## Privacy and evidence

- Use generic paths, addresses, usernames, and sample values. Never include credentials, private media names, personal library inventories, or identifying operational details.
- Describe a result only at the level that helps a contributor understand behavior or limits. Keep private deployment evidence outside the repository unless it has clear public value and has been sanitized.
- Distinguish automated tests, local checks, deployment observations, and device testing. Do not infer one from another.
- Before the first public release, review the tracked tree and Git history for sensitive values. Editing a file does not remove its earlier versions from Git history.

## Changing conventions

Edit the repository Markdown directly, using the normal Git review workflow. Editors, assistants, and skills may help; no particular tool is required. Project instructions and maintainer decisions govern the result, including where tools store their artifacts.

1. Identify a concrete problem: an ambiguous rule, duplication, recurring mistake, accepted decision, or upstream API change. Do not add rules solely to follow a trend.
2. Read the affected code, existing convention, and linked decisions. For upstream guidance, use official documentation and release notes compatible with the locked dependencies and configured toolchain. Distinguish framework requirements from Bolognesa's choices.
3. Edit the document that owns the topic. Write a short, actionable rule and link to its source or decision when the rationale matters. Update related links instead of copying the rule elsewhere.
4. Explain the reason and impact in the issue or pull request. A wording correction needs no new decision record. A change to accepted architecture needs an updated or replacement decision, with superseded records linked. Identify any existing code that still needs migration and track that work explicitly.
5. Review the complete diff for contradictions, duplication, and misleading examples. Check relative links and anchors; follow [testing conventions](testing.md) for relevant checks and record actual results. Documentation-only edits do not need artificial tests.

## Maintenance

- Use descriptive filenames and relative links. Keep an index for collections of decision records.
- Prefer editing the current document over appending a dated log.
- Remove links when their targets are removed; check all Markdown links after reorganizing documentation.
- Do not add tool-specific documentation directories. Tool workflows must follow the repository's document structure.
- Document only behavior that exists or a clearly labeled open question. Avoid duplicating instructions from the root README or contributor guide.

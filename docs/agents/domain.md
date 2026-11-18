# Domain docs

Single-context repository.

## Before exploring, read these

- `GLOSSARY.md` at the repository root, if it exists. There is none yet; use the vocabulary of the code and decisions.
- [Architecture decisions](../decisions/README.md) in `docs/decisions/` (not `docs/adr/`) that touch the area you work in.

Do not flag a missing glossary or suggest creating it upfront; `/domain-modeling` creates it when terms get resolved.

## Use the glossary's vocabulary

When output names a domain concept (issue title, refactor proposal, hypothesis, test name), use the established term. A missing term means either invented language (reconsider) or a real gap (note it for `/domain-modeling`).

## Flag decision conflicts

If output contradicts an accepted decision, say so explicitly instead of silently overriding it:

> _Contradicts decision 0011 (live transcoding), but worth reopening because…_

# 0007. Documentation organized by purpose

Status: Accepted on 2026-10-10; refined for public collaboration on 2026-10-12.

## Context

Working designs, plans, validation notes, and history had accumulated across tool-specific and overlapping folders. This made it difficult to tell current rules from temporary execution details and made the documentation expensive to maintain.

## Decision

Keep the project introduction and scope in the root README, contribution guidance in CONTRIBUTING, and durable technical rules in conventions and decision records. Track work and release scope in GitHub issues and milestones; record verification evidence in issues and pull requests. Write it in English, use relative links, and keep private deployment evidence and personal media details out of the tracked tree. Temporary designs and plans belong to the change that uses them; remove them when complete or distill lasting rules into conventions or decisions.

Use the repository's documentation structure regardless of which skill or tool helped create a document. See [documentation conventions](../conventions/documentation.md).

## Consequences

The public docs are smaller and distinguish current contracts from working notes. Removing temporary documents requires updating links; Git history retains removed content. Review the full history before the first public release and coordinate any history rewrite.

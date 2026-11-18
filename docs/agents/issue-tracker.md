# Issue tracker: GitHub

Work, specs, and verification gaps live in [GitHub issues](https://github.com/avillen/bolognesa/issues) for `avillen/bolognesa`. Use the `gh` CLI; it infers the repository from the clone.

## Operations

- **Create**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read**: `gh issue view <number> --json number,title,body,labels,comments`.
- **List**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`, with `--label` and `--state` filters as needed.
- **Sub-issue**: `gh issue create --parent <parent> ...` or `gh issue edit <parent> --add-sub-issue <child>` needs `gh` 2.94 or later. Otherwise use `gh api --method POST repos/avillen/bolognesa/issues/<parent>/sub_issues -F sub_issue_id=<child-database-id>`, or put `Part of #<parent>` at the top of the child body.
- **Comment**: `gh issue comment <number> --body "..."`.
- **Labels**: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

When a tool asks to publish to the issue tracker, create a GitHub issue. When it asks for the relevant ticket, read the issue as above.

External pull requests are not a request surface: triage covers issues only. GitHub shares one number space across issues and pull requests, so resolve a bare `#42` with `gh pr view 42` and fall back to `gh issue view 42`.

## Wayfinding

A **map** is one issue labelled `wayfinder:map` holding Notes, Decisions so far, and Fog. Its **tickets** are sub-issues labelled `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`.

- **Blocking**: use GitHub issue dependencies: `gh api --method POST repos/avillen/bolognesa/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-database-id>`, where the database id comes from `gh api repos/avillen/bolognesa/issues/<n> --jq .id`. Without dependencies, put `Blocked by: #<n>` at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier**: the map's first open, unassigned child with no open blocker.
- **Claim**: `gh issue edit <n> --add-assignee @me` before any other write.
- **Resolve**: comment the answer, close the ticket, and add a short pointer to the map's Decisions so far.

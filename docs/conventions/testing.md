# Testing conventions

Tests focus on observable behavior and protect contracts while allowing implementation changes. Keep the effort proportional to the change.

## Workflow

1. Read existing tests for the behavior being changed.
2. For functional changes, add or update a relevant scenario and verify that it fails for the expected reason.
3. Implement the smallest change that makes it pass, then refactor while preserving verified behavior.
4. Run checks appropriate to the change and `mix precommit` for meaningful implementation work.

Documentation-only and formatting changes do not need artificial red/green tests. Refactors rely on existing coverage; address relevant gaps when found.

## Test design

- Update an existing test when its behavior changes. Add a test for a distinct scenario or uncovered regression.
- Keep useful regression coverage. Do not weaken expectations just to make a test pass.
- Name tests after the rule or result they verify. Keep fixtures and helpers local and clear.
- Assert returned data, domain rules, authorization, persisted changes, and visible interface behavior. Avoid private functions, socket internals, and exact call order unless they are part of the contract.
- Choose the lowest layer that protects the behavior. Do not duplicate every scenario across every layer.

| Area | Focus |
| --- | --- |
| Domain | Invariants, transitions, and errors without a database |
| Application | Public use cases and ports; use doubles to isolate external effects |
| Persistence and infrastructure | PostgreSQL constraints, mappers, transactions, and outbox; controlled external resources |
| LiveView | LiveViewTest interactions, stable selectors, visible results, and navigation |
| Reducers, view models, and forms | Direct tests when a meaningful transition or validation warrants them |
| Jobs and events | Recovery, duplicates, stale results, durable effects, and deterministic synchronization |

Keep doubles at external boundaries. Integration tests verify guarantees doubles cannot provide, such as transaction atomicity and database constraints. Normal tests do not depend on public providers or real NAS/TV hardware. Do not change global configuration from concurrent tests.

## Verification and processes

Run focused tests during development and broaden checks when risk or project requirements call for it. Record actual commands and distinguish automated checks from manual device verification. Unit tests do not establish hardware compatibility.

- The test PostgreSQL pool must support at least five connections for concurrent tests: one sandbox owner, one coordinator, and three workers. Do not compensate for insufficient pool capacity with longer timeouts.
- Start processes with `start_supervised!/1` so they are cleaned up between tests.
- Avoid `Process.sleep/1` and `Process.alive?/1`. Monitor a process and assert on its `DOWN` message, or use `_ = :sys.get_state/1` to synchronize before a subsequent call.

# Testing conventions

Tests focus on observable behavior and protect contracts while allowing implementation changes. Keep the effort proportional to the change.

## Workflow

1. Read existing tests for the behavior being changed.
2. For functional changes, add or update a relevant scenario and verify that it fails for the expected reason.
3. Implement the smallest change that makes it pass, then refactor while preserving verified behavior.
4. Run focused checks, then `sh scripts/dev/local.sh test` (the worktree-aware wrapper for `mix precommit`) after significant work. See [CONTRIBUTING](../../CONTRIBUTING.md#native-development) for setup.

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
| Persistence and infrastructure | PostgreSQL constraints, mappers, atomic request/job insertion, and controlled external resources |
| LiveView | LiveViewTest interactions, stable selectors, visible results, and navigation |
| Reducers, view models, and forms | Direct tests when a meaningful transition or validation warrants them |
| Jobs and events | Recovery, duplicates, stale results, durable effects, and deterministic synchronization |

Keep doubles at external boundaries. Integration tests verify guarantees doubles cannot provide, such as transaction atomicity and database constraints. Normal tests do not depend on public providers or real NAS/TV hardware. Do not change global configuration from concurrent tests.

## Verification and processes

Record actual commands and results, including failures and verification limits, in the relevant issue or pull request. Distinguish automated checks from manual device verification.

- Use `Bolognesa.DataCase` for database tests. Give collaborating processes sandbox allowances; shared mode requires `async: false`. A shared sandbox connection does not prove behavior between independent transactions.
- Use distinct fixture values for unique constraints. For race/locking tests, use independent connections and deterministic coordination; keep the configured minimum pool size of five. Do not hide pool exhaustion with longer timeouts.
- Start processes with `start_supervised!/1` so they are cleaned up between tests.
- Synchronize on messages, monitors, or explicit acknowledgements instead of sleeping or polling `Process.alive?/1`. A synchronous call such as `:sys.get_state/1` can flush earlier messages sent by the same sender; it does not prove completion of work delegated to another process.
- The suite uses a one-second `assert_receive_timeout`, including LiveView's `render_async/1` completion wait. Cold module loading and database round trips can exceed ExUnit's 100ms default. This is a bounded wait for a result, not a performance assertion; use explicit measurements for latency requirements. Do not retry failed tests or bypass token verification to hide environment failures such as a clock moving backwards.

For LiveView async results, use `render_async/2` before asserting the rendered outcome or ending the test. For browser code, run `npm test` separately; `mix precommit` does not run Node tests.

See the [SQL Sandbox ownership guide](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) for allowances, shared mode, and process cleanup.

## Playback and device checks

Use the [playback verification guide](../playback-testing.md) for synthetic browser checks, FFmpeg fixtures, negotiated delivery, and their limits. Record tested formats and devices explicitly; automated checks do not establish physical-device support.

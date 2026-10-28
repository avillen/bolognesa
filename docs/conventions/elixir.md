# Elixir conventions

## Public contracts

- Add an `@spec` for every public function and macro. Place it before the first clause and cover all clauses and default arguments with one contract.
- Use named domain and port types for inputs and results, including errors. Avoid overly broad public types such as `term()` and `module()`.
- Use `String.t()` for text when its string meaning is clear; use `binary()` for opaque byte data.
- Name cross-context IDs in callbacks (for example, `library_id :: pos_integer()`). Inside the owning context, use the domain entity's ID type directly without a redundant parameter name (for example, `Movie.id()`).
- Define named adapter types on ports and use them in use-case specs. Keep `@behaviour` and `@impl true` on adapters; a typespec cannot verify that a module implements a behaviour.
- Give time values names that distinguish their meaning, such as `issued_at()` and `expires_at()`.
- Model lifecycle stages with distinct types when a value such as an ID exists only after persistence. Do not widen both stages to `id() | nil`.
- Callback implementations do not need a duplicate `@spec`; private and macro-generated functions do not require specs.

## Lookup names and results

- Prefer `fetch_<resource>/...` for single-resource lookups, returning `{:ok, value}`, `:not_found`, or `{:error, reason}`. Absence is a distinct result, not necessarily an error; reserve error tuples for failures such as authorization, persistence, or integration failures.
- Use `get_<resource>/...` when absence is an expected optional result and `value | nil` is sufficient. Do not collapse authorization, persistence, or integration failures into `nil`.
- Use `fetch_<resource>!/...` or `get_<resource>!/...` only when failure should raise an exception. Successful calls return the value directly. Expected application failures should normally use the non-bang tuple contract.
- Standard-library APIs may use `:error` (for example, `Map.fetch/2`); preserve external API contracts at their boundary. Project-owned lookup APIs distinguish `:not_found` from `{:error, reason}`.
- Name collection queries `list_<resources>/...` and predicates with `?`; do not force these operations into the single-resource lookup convention. Preserve callback names required by behaviours and framework APIs.
- Apply these names consistently across facades, use cases, ports, adapters, and callers when introducing or revising a lookup. Existing names are migrated with their contracts; do not infer a return shape from a legacy name alone.

## Struct declaration order

Define struct modules in this order, after module documentation, aliases, and other setup:

1. Field and supporting types, with each `@typedoc` beside its type.
2. `@type t` describing the complete struct.
3. `defstruct`, with `@enforce_keys` immediately before it when present.
4. Functions, with their documentation and specs.

Always write the struct body in `@type t` across multiple lines, with one field per line and the closing brace on its own line, even for small structs.

`mix format` and the configured Credo checks are the mechanical baseline. `StrictModuleLayout` checks types before structs and functions; the remaining struct layout rules are review conventions.

## Control flow and language rules

- Prefer pattern-matched clauses, guards, and `with` for clear success/error flow. Keep branching shallow; extract a named helper when it clarifies a decision, rather than forbidding all nesting.
- Keep the expected path visible. Separate validation, errors, and side effects when a branch or anonymous function hides the flow.
- Bind the result of block expressions when it is needed afterward; rebinding a variable inside an `if` or `case` branch does not update the outer binding.
- Keep one module per file. Do not use map access syntax on structs; access fields directly or use the struct's API.
- Do not create atoms from user input. Predicate names end in `?`; reserve `is_*` names for guards.
- Prefer the standard `Time`, `Date`, `DateTime`, and `Calendar` modules. Add a dependency only when the task requires it.
- Name registered processes explicitly; use unique child-spec IDs when starting multiple instances of the same module. For concurrent enumeration, consider `Task.async_stream/3` with explicit concurrency, timeout, and failure handling; do not spawn one unbounded task per item.

## Mix

- Read task options with `mix help TASK` before using unfamiliar tasks.
- Run a focused test file with `mix test path/to/test.exs`; use `mix test --failed` to rerun prior failures.
- Avoid `mix deps.clean --all` unless there is a specific reason.

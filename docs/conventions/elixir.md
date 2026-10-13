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

## Control flow and language rules

- Do not nest conditionals (`if`, `case`, `cond`, or `with`) inside another conditional in the same function. Extract the inner decision into a well-named private function.
- Keep the expected path visible. Separate validation, errors, and side effects when a branch or anonymous function hides the flow.
- Lists do not support access syntax by index. Use `Enum.at/2`, pattern matching, or `List` functions.
- Bind the result of block expressions when it is needed afterward; rebinding a variable inside an `if` or `case` branch does not update the outer binding.
- Keep one module per file. Do not use map access syntax on structs; access fields directly or use the struct's API.
- Do not create atoms from user input. Predicate names end in `?`; reserve `is_*` names for guards.
- Prefer the standard `Time`, `Date`, `DateTime`, and `Calendar` modules. Add a dependency only when the task requires it.
- Give named OTP processes explicit child-spec names. Use `Task.async_stream/3` for concurrent enumeration with back-pressure and select its timeout deliberately.

## Mix

- Read task options with `mix help TASK` before using unfamiliar tasks.
- Run a focused test file with `mix test path/to/test.exs`; use `mix test --failed` to rerun prior failures.
- Avoid `mix deps.clean --all` unless there is a specific reason.

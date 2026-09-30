# H1 Administrator Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create one administrator through a first-run web form, then require a revocable session for the protected Inicio page.

**Architecture:** `Bolognesa.Identity` is the public backend facade. Small application operations use a repository port; domain structs and rules are independent of Ecto. The web layer resolves a database-backed session into `current_scope`, while LiveViews own presentation state and controllers change the HTTP session cookie.

**Tech Stack:** Elixir, Phoenix 1.8, LiveView, Ecto/PostgreSQL, `bcrypt_elixir`, ExUnit/LiveViewTest, Tailwind CSS 4.

**Spec:** [H1 design](../specs/2026-09-30-admin-access-design.md). Read it and `docs/plans/first-milestone.md`, `docs/conventions/backend.md`, `docs/conventions/frontend.md`, `docs/conventions/testing.md`, and `docs/conventions/observability.md` before editing. Inspect Git status and existing changes.

## Global Constraints

- Setup is open only until the first administrator is created. The database, not a UI check, resolves simultaneous submissions.
- One administrator, with real name, normalized unique email, and bcrypt password hash; no public registration after setup and no password recovery in H1.
- Session tokens are random, stored only as SHA-256 hashes, and expire 30 days after creation without sliding renewal. Logout revokes only the current token.
- Existing QNAP HTTP is accepted only in the LAN. Do not mark its cookie `Secure` while it remains HTTP; require HTTPS before future remote access.
- Domain and application code do not depend on Phoenix or Ecto. UI calls the facade and never accesses persistence schemas. No credentials, tokens, or private media paths in logs.
- Each LiveView template starts with `<Layouts.app flash={@flash} current_scope={@current_scope}>`; forms use `to_form`, `<.form>`, and `<.input>`. Use Tailwind and custom CSS rather than daisyUI for new UI.
- Keep H1 independent of libraries, movies, TV pairing, email delivery, and background jobs.

## Review Focus

1. Two valid setup POSTs at once: exactly one administrator exists; the loser receives `:setup_closed`. Test in Task 1 with independent sandbox connections.
2. A blank, mixed-case, or Unicode email: reject blank/malformed input, normalize valid ASCII case and whitespace, reject unsupported Unicode email without crashing, and enforce uniqueness after normalization. Test in Task 1.
3. A password over bcrypt's 72-byte input limit: reject it rather than silently truncate; test in Task 1.
4. A missing, malformed, expired, or revoked session token: deny protected access without crashing or returning a stale actor; test in Tasks 2 and 3.
5. A stale setup form submitted after another client finishes setup: do not create a second account, and redirect to login; test in Task 4.

---

### Task 1: First administrator and persistence

**Files:**
- Modify: `mix.exs`, `mix.lock`, `config/test.exs`
- Create: generated `priv/repo/migrations/*_create_identity_tables.exs`
- Create: `lib/bolognesa/identity/domain/user.ex`, `lib/bolognesa/identity/domain/actor.ex`, `lib/bolognesa/identity/application/install_admin.ex`, `lib/bolognesa/identity/application/ports/repository.ex`
- Create: `lib/bolognesa/identity/infrastructure/persistence/user_schema.ex`, `lib/bolognesa/identity/infrastructure/persistence/user_mapper.ex`, `lib/bolognesa/identity/infrastructure/persistence/ecto_repository.ex`, `lib/bolognesa/identity.ex`
- Test: `test/bolognesa/identity/install_admin_test.exs`

**Interfaces:**
- Produces: `Identity.setup_status() :: {:ok, :open | :closed} | {:error, :unavailable}`; `Identity.install_admin(map) :: {:ok, Actor.t()} | {:error, {:invalid, map()} | :setup_closed | :unavailable}`; `Identity.authorize(Actor.t(), :admin) :: :ok | {:error, :forbidden}`. `Actor` has `id`, `name`, `email`, `role`.
- Repository port: `admin_exists?/0`, `insert_initial_admin(User.t(), binary())`, `find_user_by_email(binary())`; errors are translated to stable terms. Later tasks extend this one port rather than inventing another dependency mechanism.

- [ ] **Step 1: Add failing domain and integration tests.** Cover valid name/email/password, trimmed lower-case ASCII email, malformed/blank/Unicode email, password shorter than 12 characters or longer than 72 bytes, duplicate setup, concurrent setup, no persisted plain password, and `authorize/2` accepting only an administrator actor. Use `Bolognesa.DataCase`; run the concurrent case with `async: false`, a `Task.Supervisor` started by `start_supervised!/1`, a message barrier before both inserts, and `Ecto.Adapters.SQL.Sandbox.allow/3` for both tasks. Assert exactly one row after both finish. Core assertions:

```elixir
assert {:ok, actor} = Identity.install_admin(%{name: "Ada", email: "  ADA@Example.COM ", password: "correct horse battery staple"})
assert actor.email == "ada@example.com"
assert {:error, :setup_closed} = Identity.install_admin(%{name: "Other", email: "other@example.com", password: "another long password"})
assert Repo.aggregate(UserSchema, :count) == 1
```

```elixir
supervisor = start_supervised!(Task.Supervisor)
parent = self()
tasks = for email <- ["one@example.com", "two@example.com"] do
  Task.Supervisor.async_nolink(supervisor, fn ->
    send(parent, {:ready, self()})
    receive do :go -> Identity.install_admin(%{name: "Admin", email: email, password: "correct horse battery staple"}) end
  end)
end
pids = for _ <- tasks do assert_receive {:ready, pid}; :ok = Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid); pid end
Enum.each(pids, &send(&1, :go))
assert Enum.sort(Enum.map(tasks, &Task.await/1) |> Enum.map(fn {:ok, _} -> :ok; {:error, reason} -> reason end)) == [:ok, :setup_closed]
```

- [ ] **Step 2: Run** `mix test test/bolognesa/identity/install_admin_test.exs`. Expect a failure because `Identity.install_admin/1` does not exist.
- [ ] **Step 3: Add bcrypt and generate the migration** using `mix ecto.gen.migration create_identity_tables` (its help has been checked). Define `identity_users` with `name`, `email`, `role`, `hashed_password`, timestamps; unique email index and partial unique index for `role = 'admin'`. Never place a password in seeds or config. Configure low bcrypt rounds only for tests; normal builds use the library default.

```elixir
create unique_index(:identity_users, [:email])
create unique_index(:identity_users, [:role], where: "role = 'admin'", name: :identity_one_admin)
```

- [ ] **Step 4: Implement the smallest domain, application, mapper, adapter, and facade** supporting the tests. `User.new_admin/1` returns normalized validated identity or field errors; `InstallAdmin.call(attrs, repository, hasher)` validates before hashing and asks the repository to perform the single insert transaction. Map the partial-index violation to `:setup_closed`, including a stale form race. The facade supplies `EctoRepository` and a bcrypt adapter explicitly; tests may inject fakes into the operation, but integration tests use PostgreSQL. Define one `PasswordHasher` behaviour if needed, beside the repository port; do not expose Ecto schemas through the facade.
- [ ] **Step 5: Run** `mix format`, then `mix test test/bolognesa/identity/install_admin_test.exs` and `mix format --check-formatted`. Expect success. Commit the task.

### Task 2: Credential verification and durable sessions

**Files:**
- Create: generated `priv/repo/migrations/*_create_identity_sessions.exs`
- Modify: repository port/adapter, `lib/bolognesa/identity.ex`
- Create: `lib/bolognesa/identity/domain/session.ex`, `lib/bolognesa/identity/application/start_session.ex`, `lib/bolognesa/identity/application/resolve_session.ex`, `lib/bolognesa/identity/application/end_session.ex`, `lib/bolognesa/identity/infrastructure/persistence/session_schema.ex`, `lib/bolognesa/identity/infrastructure/persistence/session_mapper.ex`
- Test: `test/bolognesa/identity/session_test.exs`

**Interfaces:**
- Consumes: `Actor`, `UserSchema`, `UserMapper`, repository, bcrypt adapter from Task 1.
- Produces: `Identity.start_session(email, password) :: {:ok, raw_token} | {:error, :invalid_credentials | :unavailable}`; `Identity.fetch_actor(raw_token) :: {:ok, Actor.t()} | {:error, :unauthenticated | :unavailable}`; `Identity.end_session(raw_token) :: :ok | {:error, :unavailable}`. Repository adds `insert_session(user_id, token_hash, expires_at)`, `find_active_session(token_hash, now)`, `delete_session(token_hash)`.

- [ ] **Step 1: Write failing integration tests** for valid credentials, unknown email and wrong password returning the same error, a fresh token resolving to the right actor, two devices receiving distinct tokens, 30-day absolute expiry, revoking one token while the other works, and malformed token input. Insert an expired session directly through the repository/schema for the expiry case. For unknown email call bcrypt verification against a fixed dummy hash to avoid a trivial timing difference.

```elixir
{:ok, first} = Identity.start_session("ada@example.com", "correct horse battery staple")
{:ok, second} = Identity.start_session("ada@example.com", "correct horse battery staple")
assert first != second
assert :ok = Identity.end_session(first)
assert {:error, :unauthenticated} = Identity.fetch_actor(first)
assert {:ok, %Actor{email: "ada@example.com"}} = Identity.fetch_actor(second)
```

- [ ] **Step 2: Run** `mix test test/bolognesa/identity/session_test.exs`; expect failure for missing session functions.
- [ ] **Step 3: Implement** session storage with 32 random bytes encoded URL-safe for the cookie, SHA-256 hash in PostgreSQL, `inserted_at`, `expires_at`, `user_id`, a unique index on `token_hash`, and an index on `user_id`. Generate the second migration with `mix ecto.gen.migration create_identity_sessions`; do not edit the Task 1 migration after it has run. Never store or log the raw token. Compare expiry to `DateTime.utc_now()` on each resolution and do not renew it. Use the repository port from Task 1 and map database failure to `:unavailable`; absence, malformed input, and expiry to `:unauthenticated`. Do not catch all exceptions and mislabel infrastructure failure as invalid credentials.
- [ ] **Step 4: Run** `mix format`, the session and setup test files, then `mix format --check-formatted`. Expect success. Commit the task.

### Task 3: HTTP session, protected routing, and authorization boundary

**Files:**
- Create: `lib/bolognesa_web/user_auth.ex`, `lib/bolognesa_web/controllers/session_controller.ex`
- Modify: `lib/bolognesa_web/router.ex`, `lib/bolognesa_web/endpoint.ex`
- Test: `test/bolognesa_web/controllers/session_controller_test.exs`, `test/bolognesa_web/user_auth_test.exs`

**Interfaces:**
- Consumes: `Identity.start_session/2`, `fetch_actor/1`, `end_session/1`.
- Produces: `conn.assigns.current_scope` containing `%{actor: %Actor{}}` for verified sessions, `nil` on public routes. The existing `/` controller is temporarily protected by the plug; the protected LiveView mount follows in Task 5. Unauthenticated clients redirect to `/login` when setup is closed, or `/setup` when open.

- [ ] **Step 1: Write failing ConnCase tests**: anonymous `/` redirects; POST `/login` with valid credentials renews session and reaches `/`; invalid credentials redirect to `/login` with generic feedback and no session; DELETE `/logout` revokes only the current cookie token; replaying an old session cookie is rejected. Exercise the unavailable-store branch through a small result-handling function in `UserAuth` and assert a generic 503 without exposing a token. Verify CSRF protection remains on browser routes and that credentials do not enter redirect URLs. The GET `/login` screen arrives in Task 5, so assert the redirect target here rather than following it.

```elixir
conn = post(conn, ~p"/login", %{"login" => %{"email" => "ada@example.com", "password" => "correct horse battery staple"}})
assert redirected_to(conn) == ~p"/"
assert get_session(conn, :user_token)
```

- [ ] **Step 2: Run** the two new test files. Expect route/function-not-found failures.
- [ ] **Step 3: Implement** `UserAuth.fetch_current_scope/2`, `require_authenticated_user/2`, and `on_mount(:require_authenticated, params, session, socket)` using only `Identity.fetch_actor/1`. `SessionController.create/2` calls `Identity.start_session/2`, invokes `configure_session(renew: true)`, stores only the raw token in the signed, `HttpOnly`, `SameSite=Lax` Plug session cookie, and redirects. Set the cookie's `max_age` to 30 days (`2_592_000` seconds) so closing the browser does not end a still-valid database session; the database expiry remains authoritative. `delete/2` clears the Plug session and redirects only after `Identity.end_session/1` returns `:ok`; on storage failure it shows a generic error and does not claim revocation. An unavailable session store fails closed with a generic 503 response. Use literal redirect paths `/setup` and `/login` until their GET routes arrive in Tasks 4 and 5. Leave `Secure` dependent on a future HTTPS deployment, as the current QNAP URL is HTTP.
- [ ] **Step 4: Route** POST `/login` in the browser pipeline, keep the current `PageController` at `/` behind `require_authenticated_user`, and place DELETE `/logout` behind that plug. Tasks 4 and 5 replace the generated page and add the public LiveView routes and protected `live_session`. A router plug alone does not protect a live reconnect, so Task 5 must test both mounts.
- [ ] **Step 5: Run** `mix format`, then `mix test test/bolognesa_web/controllers/session_controller_test.exs test/bolognesa_web/user_auth_test.exs`. Expect success. Commit the task.

### Task 4: One-time setup screen

**Files:**
- Create: `lib/bolognesa_web/live/setup/live.ex`, `live.html.heex`, `forms/admin.ex`, `reducers/initialize.ex`, `reducers/validate.ex`, `reducers/save.ex`
- Test: `test/bolognesa_web/live/setup/live_test.exs`

**Interfaces:**
- Consumes: `Identity.setup_status/0`, `Identity.install_admin/1` and public `/setup` route.
- Produces: `#setup-form` with `#setup-name`, `#setup-email`, `#setup-password`, `#setup-password-confirmation` and a submit button; success navigates to `/login`.

- [ ] **Step 1: Write failing LiveView tests** for empty installation, field errors, successful submission, page unavailable after setup, and a stale already-open form submitted after another request creates the administrator. Test by stable IDs using `has_element?/2`, `element/2`, `render_change/2`, and `render_submit/2`.

```elixir
{:ok, view, _html} = live(conn, ~p"/setup")
assert has_element?(view, "#setup-form")
view |> form("#setup-form", admin: %{name: "Ada", email: "ada@example.com", password: "correct horse battery staple", password_confirmation: "correct horse battery staple"}) |> render_submit()
assert_redirect(view, ~p"/login")
```

- [ ] **Step 2: Run** `mix test test/bolognesa_web/live/setup/live_test.exs`; expect missing LiveView failure.
- [ ] **Step 3: Implement** the public `/setup` LiveView route and `Forms.Admin` as an embedded schema used only for UI validation; the backend repeats all rules. `Initialize`, `Validate`, and `Save` reducers each expose `call(socket, ...)` and return a socket. Assign `to_form(changeset)` from reducers. Translate `{:error, {:invalid, fields}}` into form errors, `:setup_closed` into navigation to `/login` (the screen arrives in Task 5), and `:unavailable` into a generic retry message. Do not return entered passwords in flashes or logs. The HEEx template begins with `<Layouts.app flash={@flash} current_scope={@current_scope}>` and uses `<.input>` for every field. Ensure `current_scope` is assigned as `nil` on the public LiveView.
- [ ] **Step 4: Run** `mix format` and the setup LiveView and Task 1 test files; expect success. Commit the task.

### Task 5: Login, protected Inicio, and visual shell

**Files:**
- Create: `lib/bolognesa_web/live/login/live.ex`, `live.html.heex`, `forms/login.ex`, `reducers/initialize.ex`
- Create: `lib/bolognesa_web/live/home/live.ex`, `live.html.heex`, `reducers/initialize.ex`
- Modify: `lib/bolognesa_web/components/layouts.ex`, `lib/bolognesa_web/components/layouts/root.html.heex`, `assets/css/app.css`
- Remove: old `lib/bolognesa_web/controllers/page_controller.ex`, `page_html.ex`, `page_html/home.html.heex` after replacing the route
- Modify: `test/bolognesa_web/controllers/page_controller_test.exs` to replace it with LiveView behavior tests under `test/bolognesa_web/live/home/live_test.exs`
- Test: `test/bolognesa_web/live/login/live_test.exs`, `test/bolognesa_web/live/home/live_test.exs`

**Interfaces:**
- Consumes: `current_scope` from Task 3 and the controller POST `/login`.
- Produces: `#login-form`, `#home-screen`, `#logout-button`; the login form posts to `/login`, while logout sends DELETE `/logout` with CSRF protection.

- [ ] **Step 1: Write failing LiveView tests** showing login form presence, a login submission's browser action, successful authenticated Inicio with the correct name, anonymous redirect, and logout control. Replace the generated Phoenix page text assertion with these observable behaviors; preserve error controller tests.

```elixir
{:ok, view, _html} = live(conn, ~p"/login")
assert has_element?(view, "#login-form")
refute has_element?(view, "#home-screen")
```

- [ ] **Step 2: Run** the two LiveView test files; expect missing-screen failures.
- [ ] **Step 3: Implement** public GET `/login` and protected LiveView `/` in separate `live_session` groups. Apply `UserAuth.on_mount(:require_authenticated, ...)` to the protected group, and assign `current_scope` to the public login view. Test both the initial HTTP request and connected LiveView mount. `Forms.Login` and its `Initialize` reducer assign `to_form/2`. Use `<.form for={@form} action={~p"/login"} method="post" id="login-form">` so the browser POST reaches `SessionController`; do not keep the password in LiveView socket state. The Inicio reducer maps the verified actor to simple display assigns. Include a visible POST form with `_method=delete` and CSRF token for logout, or Phoenix's supported equivalent; test the actual rendered and submitted behavior.
- [ ] **Step 4: Replace** the generated page and daisyUI presentation with a warm dark Tailwind shell matching the approved UX direction. Keep existing Tailwind v4 import syntax, use `<.icon>` and `<.input>`, add visible keyboard focus and comfortable touch targets, and preserve layout flash handling only inside `Layouts`. Set Spanish page titles/copy and appropriate `lang="es"`. Check at narrow mobile and desktop widths; do not add movie cards or TV controls.
- [ ] **Step 5: Run** `mix format`, both LiveView tests, controller tests, and `mix assets.build`. Expect success. Commit the task.

### Task 6: Operational instructions and final verification

**Files:**
- Modify: `deploy/qnap/README.md`, `docs/status.md`, `docs/roadmap.md`, `docs/plans/first-milestone.md`
- Create: `docs/decisions/0002-initial-access.md`; modify `docs/decisions/README.md` to index the significant first-run and session boundary choice

**Interfaces:**
- Consumes: the working setup/login/logout flow and existing `make qnap-deploy` / `make qnap-update` commands.
- Produces: a reproducible first-run procedure and an honest status snapshot. H1 is marked complete only if its acceptance criteria and required checks pass.

- [ ] **Step 1: Verify the complete flow locally** with database reset in an isolated test database, not the deployed QNAP: open setup, submit once, sign in, reach Inicio, sign out, replay the old session, and sign in again. Prefer automated ConnCase/LiveViewTest for these outcomes; add a missing integration test if this sequence reveals a gap.
- [ ] **Step 2: Update QNAP instructions** to deploy and migrate first, then immediately visit `/setup` from the LAN, create the administrator, verify `/setup` closes, log in, and log out. State the first-visitor appropriation window, lack of password recovery, HTTP credential/session exposure, and HTTPS prerequisite for remote access. Record the rationale and accepted tradeoffs in decision 0002 and index it. Do not print or record credentials. Do not claim QNAP verification unless performed.
- [ ] **Step 3: Run** `mix precommit` and `git diff --check`; fix failures. Review `git status`, update `docs/status.md` with actual implementation, checks, blockers, and next step, and mark H1 complete in `docs/roadmap.md` only when every acceptance criterion is met. Commit the final docs and any fixes.

## Execution notes

Tasks are ordered because web authentication depends on the identity facade, and screens depend on router/session behavior. Test changes should fail for the expected reason before implementation. Review generated `phx.gen.auth` code as a reference, but do not adopt its public registration or email link flows. Run `mix help` before using unfamiliar Mix tasks. The current QNAP deployment is not part of an automatic implementation run: build, deploy, migration, and device observations require their own explicit verification record.

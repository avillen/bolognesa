# Phoenix, LiveView, and UI conventions

Follow the project's pinned Phoenix 1.8 and LiveView APIs. [Frontend conventions](frontend.md)
own screen organization and presentation state; [backend conventions](backend.md) own domain,
Ecto, query, and transaction rules.

## Router and security

- Group routes by browser/session requirements. Authenticate in the HTTP pipeline and in
  LiveView `mount`/`on_mount`; navigation within a `live_session` bypasses the plug pipeline.
- Pass the trusted caller to protected backend operations, which enforce authorization
  on every read and mutation, including events and parameter changes. Hidden controls,
  client-supplied IDs, and authenticated mounts do not grant resource access.
- Media endpoints reauthorize every request and return media responses rather than page redirects.
- Keep CSRF protection for state-changing browser requests and secrets in runtime configuration.
- Authorize PubSub subscriptions; topic names do not grant access. Treat notifications as
  hints and re-fetch authoritative state through the owning facade.

See the official [LiveView security model](https://hexdocs.pm/phoenix_live_view/security-model.html). Sensitive event and parameter logging follows [observability conventions](observability.md#logs-and-privacy).

## HEEx, forms, and accessibility

- Use HEEx and existing function components instead of string-built HTML. Escape untrusted
  text normally; never mark user or provider content as safe HTML. Keep attribute names
  code-owned; do not spread untrusted maps into HEEx attributes.
- Use `<.form>` with `to_form/2` and shared `<.input>` components. Keep submitted values on
  validation errors and show errors beside their fields; use the presentation forms described
  in [frontend conventions](frontend.md#presentation-state-and-forms).
- Use the existing Tailwind setup, semantic CSS tokens, and CoreComponents. Keep styles in
  `assets/css/app.css` or files it imports.
- Target [WCAG 2.2 AA](https://www.w3.org/TR/WCAG22/). Use semantic HTML, labels,
  accessible names, visible focus, and controls operable by touch,
  keyboard, and remote control. Essential actions must not depend on hover or color alone.
  Dialogs need predictable focus entry, dismissal, and return. Respect reduced-motion preferences.
  Announce asynchronous status and validation feedback with appropriate live regions.
  Pointer targets need at least 24 by 24 CSS pixels or an applicable WCAG 2.2 exception.
- Native dialogs and disclosures own their open state. Preserve `open` across LiveView
  patches with `JS.ignore_attributes("open")`; reconcile server-driven changes explicitly.
- Build mobile-first. Verify device navigation and playback on the target device separately
  from synthetic browser checks.

## LiveView and hooks

- Use streams for growing or paginated collections. Give the container an ID and
  `phx-update="stream"`, and each direct child its stream DOM ID. Do not alter those IDs.
  Reset streams when filters change. Bound both the query and rendered collection; stream
  limits do not limit the initial query or first render. Pass the limit on later inserts too.
- Use `assign_async/3` for async assigns, `stream_async/4` for async streams, or
  `start_async/3` with `handle_async/3` for custom coordination. Capture only required
  inputs, never the socket. Handle failures and stale results explicitly; durable jobs
  belong in the backend, not LiveView tasks.
- Put browser code and hooks in the context-owned directories described in
  [frontend conventions](frontend.md#templates-components-and-browser-code). Register hooks
  in `assets/js/app.js`. Add JavaScript only for browser APIs or immediate interactions;
  use `Phoenix.LiveView.JS` for supported
  DOM operations. Do not add ordinary inline scripts to templates.
- Give hook elements stable, unique IDs. When a library owns a DOM subtree, use
  `phx-update="ignore"` on its identified host and update it through the hook. Ignoring
  patches is a DOM ownership choice, not a way to suppress server-side state updates.
- Use documented hook/event APIs. Clean up timers, listeners, observers, and player instances
  in `destroyed`; handle reconnects when an interaction depends on the connection.
- Send meaningful playback actions or progress to the server, rather than every frame.
  State ownership follows [frontend conventions](frontend.md#templates-components-and-browser-code).

Follow the [LiveView API reference](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
and [testing conventions](testing.md) for interaction checks.

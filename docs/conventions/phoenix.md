# Phoenix, LiveView, and UI conventions

Follow the project's pinned Phoenix 1.8 and LiveView APIs. [Frontend conventions](frontend.md)
own screen organization and presentation state; [backend conventions](backend.md) own domain,
Ecto, query, and transaction rules.

## Router and security

- Group routes by browser/session requirements. Authenticate in the HTTP pipeline and in
  LiveView `mount`/`on_mount`; navigation within a `live_session` bypasses the plug pipeline.
- Authorize backend reads and mutations, including events and parameter changes. Hidden
  controls, client-supplied IDs, and authenticated mounts do not grant resource access.
- Media endpoints reauthorize every request and return media responses rather than page redirects.
- Keep CSRF protection for state-changing browser requests and secrets in runtime configuration.
- Authorize PubSub subscriptions; topic names do not grant access. Treat notifications as
  hints and re-fetch authoritative state through the owning facade.

See the official [LiveView security model](https://hexdocs.pm/phoenix_live_view/security-model.html).

## HEEx, forms, and accessibility

- Use HEEx and existing function components instead of string-built HTML. Escape untrusted
  text normally; never mark user or provider content as safe HTML.
- Use `<.form>` with `to_form/2` and shared `<.input>` components. Keep submitted values on
  validation errors and show errors beside their fields; use the presentation forms described
  in [frontend conventions](frontend.md#presentation-state-and-forms).
- Use the existing Tailwind setup, semantic CSS tokens, and CoreComponents. Keep styles in
  `assets/css/app.css` or files it imports.
- Use semantic HTML, labels, accessible names, visible focus, and controls operable by touch,
  keyboard, and remote control. Essential actions must not depend on hover or color alone.
  Dialogs need predictable focus entry, dismissal, and return. Respect reduced-motion preferences.
- Build mobile-first. Verify device navigation and playback on the target device separately
  from synthetic browser checks.

## LiveView and hooks

- Use streams for growing or paginated collections. Give the container an ID and
  `phx-update="stream"`, and each item its stream DOM ID. Reset streams when filters change;
  use stream limits when accumulating pages would otherwise grow browser state indefinitely.
- Use `assign_async/3` for async assigns or `start_async/3` with `handle_async/3` for custom
  coordination. Capture only required inputs, never the socket. Handle failures and stale
  results explicitly; durable jobs belong in the backend, not LiveView tasks.
- Hooks live in `assets/js/hooks/` and are imported by `assets/js/app.js`. Add JavaScript
  only for browser APIs or immediate interactions; use `Phoenix.LiveView.JS` for supported
  DOM operations. Do not add ordinary inline scripts to templates.
- Use documented hook/event APIs. Clean up timers, listeners, observers, and player instances
  in `destroyed`; handle reconnects when an interaction depends on the connection.
- Keep immediate playback state in the browser and send meaningful actions or progress,
  rather than every frame. See [frontend state ownership](frontend.md#templates-components-and-browser-code).

Follow the [LiveView API reference](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
and [testing conventions](testing.md) for interaction checks.

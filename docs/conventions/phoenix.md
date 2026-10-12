# Phoenix, LiveView, and UI conventions

Follow existing Phoenix 1.8 patterns and the project's layout and component conventions. Keep interface behavior in LiveView and presentation modules, and keep business rules in backend contexts.

## Components and styling

- Use the existing Tailwind setup and shared CoreComponents. Prefer reusable function components for stateless presentation.
- Keep JavaScript small and scoped to hooks. Avoid adding dependencies or one-off global behavior without a concrete need.
- Design mobile-first with clear hierarchy, useful empty and error states, visible focus, and controls that work by touch and keyboard.
- Use semantic HTML, labels, and accessible names. Do not rely on color or hover alone to communicate state.

## Router and security

- Group routes by browser/session requirements and use pipelines for shared behavior.
- Protect authenticated pages and actions on the server. A LiveView mount or hidden button is not authorization.
- Media endpoints must re-authorize every request and return media responses rather than browser-page redirects.
- Use CSRF protections for state-changing browser requests. Keep secrets in runtime configuration.

## Ecto

- Keep schemas and queries in persistence adapters. Use changesets for persistence constraints and database constraints for invariants that must survive concurrency.
- Build queries with explicit fields, ordering, and pagination. Avoid loading unbounded collections.
- Keep transactions short. Do not hold a transaction during HTTP calls, filesystem scans, or media inspection.
- Do not pass persistence schemas or changesets through public context APIs.

## HEEx and forms

- Use function components and HEEx attributes; avoid string-built HTML.
- Use `<.form>` and shared `<.input>` components with changesets or form data prepared by the LiveView.
- Preserve submitted values on validation errors and show errors next to the relevant controls.
- Escape untrusted text through normal HEEx rendering. Do not mark user or provider content as safe HTML.

## LiveView

- Keep LiveViews focused on lifecycle and event delegation. Put coherent presentation operations in screen-local reducers.
- Use streams for growing or paginated collections. Give streamed elements stable DOM IDs and follow the stream reset/insert rules when state changes.
- Run slow work asynchronously with only the required input data. Handle success, failure, and stale results explicitly.
- Re-fetch authoritative state after notifications; PubSub messages are hints and are not a source of truth.
- Authorize PubSub subscriptions and every backend read or write. A topic name does not grant access.

### JavaScript hooks and events

Use colocated or external hooks only when the browser API or immediate interaction requires JavaScript. Keep hooks focused, clean up listeners and timers, and use documented LiveView event APIs. Browser-owned playback state should be sent only when it carries useful application meaning, not on every frame.

## LiveView tests

Test through `Phoenix.LiveViewTest` and stable selectors. Assert rendered behavior, navigation, validation feedback, and authorization outcomes. Keep process and synchronization guidance in [testing conventions](testing.md).

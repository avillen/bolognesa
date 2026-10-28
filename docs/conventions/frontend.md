# Frontend conventions

This document defines Bolognesa's web presentation rules. It complements [Phoenix and UI](phoenix.md), [backend](backend.md), and [testing](testing.md) conventions.

## Organize by screen

Each screen owns its LiveView, template, reducers, view models, forms, and screen-specific components. Use a singular `reducer/` directory for coherent presentation operations; keep trivial assignments in the caller. Add directories only when a feature needs them.

```text
lib/bolognesa_web/live/movie/index/
  live.ex
  live.html.heex
  reducer/load.ex
  state/movie.ex
  forms/filters.ex
  components/movie_card.ex
```

Module names follow the path, such as `BolognesaWeb.Movie.Index.Reducer.Load`. This screen-based structure replaces the generic `movie_live/index.ex` layout for new screens.

## LiveViews and reducers

LiveViews handle lifecycle, params, events, messages, and async results, returning the tuples required by LiveView. Reducers coordinate presentation and call public backend facades.

Each reducer exposes `call(socket, ...)`, takes the socket first, and always returns a socket. Extra arguments carry the data needed for the operation. A reducer may call the backend, update assigns or streams, and start LiveView effects; it is not necessarily a pure function.

- Reducers contain UI coordination, not business rules or direct queries to backend schemas and private repositories.
- Backend use cases enforce rules and authorization.
- Use a coordinator reducer when later steps depend on an earlier step's success.
- A public reducer represents a coherent operation; do not make a module for each simple `assign`.
- Keep reducers with their screen instead of creating a global reducer module.

## Presentation state and forms

The socket owns screen state. Do not duplicate all assigns and streams in a parallel state struct. Put screen-specific view models in `state/`; they contain only prepared display data and remain independent of domain entities and persistence schemas. Stream items need stable identities. Use assigns for simple state and small bounded collections, and streams for growing or paginated collections; extract shared stream helpers only after real reuse appears.

Put presentation-only models and changesets in `forms/`, using embedded schemas or schema-less changesets. They validate input shape and required fields; the backend validates business rules again. Do not expose persistence schemas to the UI. Web params arrive with string keys; convert validated form data to the atom-keyed shape promised by the backend facade.

## Loading, errors, and navigation

- Run slow work with LiveView async operations, following the [Phoenix API guidance](phoenix.md#liveview-and-hooks).
- Discard stale responses so an older request cannot replace a newer result.
- Keep loading, empty, and error states distinct. A failed refresh is not an empty collection.
- Reducers translate backend results and async failures into visible UI state and feedback.
- Put navigable filters, search, and sort in the URL and interpret them through `handle_params`.
- Hierarchical return links lead to the parent screen and preserve validated library, search, and pagination context. Keep per-tab scroll restoration bounded and normalize equivalent URLs before using them as storage keys.
- Durable work such as library scans belongs to the backend and continues when a page closes.

## Templates, components, and browser code

The screen template lives beside its LiveView. Function components receive attributes and emit events; they do not query the backend. Use LiveComponents only when their own state or lifecycle is needed. Keep components within the screen until real reuse justifies a shared location.

LiveView templates start with `<Layouts.app flash={@flash} ...>`. Follow [Phoenix conventions](phoenix.md) for HEEx, hooks, forms, and accessible interactions.

The browser owns immediate player state such as position, volume, and fullscreen. Send meaningful actions and progress to the backend; do not send every visual update.

Native dialogs and disclosures also own their open state. Preserve their `open` attribute across LiveView patches with `JS.ignore_attributes("open")`. Keep responsive navigation accessible when changing between mobile and desktop.

## Visual design

Use semantic CSS tokens from `assets/css/app.css`. The current design uses a dark charcoal base, warm white text, and coral accents. Preserve contrast, visible focus, semantic error/success colors, and reduced-motion preferences. Missing poster art must have a useful fallback. Keep actions and data tied to existing behavior; presentation changes do not imply new product capabilities.

## Interface language

Use Gettext for application-owned UI strings, with complete English and Spanish catalogs, pluralization, interpolation, and accessible labels. Do not translate backend reason codes or stored catalog data. Resolve locale at the web boundary using the signed-in account preference, browser language, then Spanish fallback. Never change process-global locale configuration per request.

Translate changeset messages when displaying them, without translating them twice. Async work should return data; prepare localized text in the presentation process or pass an explicit locale. The account language setting requires a full reload; already open tabs update when reloaded. See [decision 0016](../decisions/0016-user-locale-and-settings.md).

## Verification

Follow [testing conventions](testing.md). Cover loading, error, empty, stale-response, form, and stream behavior where relevant, without duplicating every interaction at the reducer level.

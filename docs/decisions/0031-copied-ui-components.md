# 0031. Copied SaladUI components on semantic tokens

Status: Implemented.

## Context

Screens style controls with screen CSS and ad hoc Tailwind classes, so buttons,
cards and status messages drift between contexts. SaladUI 1.0 ports shadcn/ui to
Phoenix LiveView: an installer copies function components, JavaScript hooks and
CSS tokens into the application, which then owns them.

The unreviewed installer output did not fit Bolognesa. It added a module outside
`BolognesaWeb`, about 16,000 lines for 40 components, and 15 JavaScript imports
for interactive components that no screen uses. It also added a second
`@import "tailwindcss"` without `source(none)`, which scans the whole project and
its dependencies. Its light and `.dark` token sets overrode the coral `accent`
and every Tailwind radius. Its global `border-color: hsl(var(--border))` was
invalid, because the token values are OKLCH. `salad_ui` also brings `igniter` and
`sourceror` in as runtime dependencies.

## Decision

- Use SaladUI as a source to copy from, not as a framework. Keep only the
  components a screen uses under `lib/bolognesa_web/components/ui/`
  (`BolognesaWeb.Components.UI.*`) and add more only when a screen needs them.
  Every HTML module aliases `Alert`, `Button` and `Card` and imports
  `button_variant/2`. Calls go through the aliases, such as `<Button.button>`,
  because the component names overlap with CoreComponents.
- Adapt the copies to the house: every button size keeps 44px targets
  (`min-h-11`, icon `size-11`), and Card takes a `tag` so list items stay
  `<article>`. Repeated house looks become variants instead of call-site
  classes: `play` (coral glow), `subtle` (bordered, muted secondary icon
  control), `nav` (its own geometry and `aria-current` highlight), the `pill`
  shape and the `round` icon size (shorthand for `icon` with `pill`). These
  components replace the `media-*-action` and `library-*` button classes, the
  per-screen error styles and the visual rules of player, track, album and
  sidebar controls. Screen CSS keeps placement and state hooks only.
- Put `.app-content button` in `@layer base`, so component utilities override
  it. Queue menu buttons that JS creates take their look from a rule scoped to
  their menu (`.music-menu-items button`), not from a rule on every player button.
  The global focus outline stays unlayered, because some inputs use
  `outline-none` and depend on it.
- Keep `salad_ui` as a dev-only dependency for future copies and upstream diffs.
  Depend directly on `tw_merge`, which the copied components use at runtime,
  and start its `TwMerge.Cache` first in the application supervision tree.
- Map shadcn's semantic tokens onto the existing dark palette in one
  `@theme inline` block in `app.css`. Where the names clash, Bolognesa's meaning
  wins: `accent` is the coral brand colour and `muted` is secondary text. The
  copied components use `secondary` for shadcn's hover surface and
  `muted-foreground` for secondary text. `primary-foreground` is `canvas`, because
  `ink` on coral has a contrast of 2.6:1.
- Keep accessibility semantics in the markup that renders a component. Section
  navigation stays links with `aria-current`, styled through `button_variant/2`,
  rather than ARIA tabs.
- Adopt interactive SaladUI components (dialog, select, tabs, toast and others)
  only after a separate review of their JavaScript against the native dialog and
  hook conventions.

## Consequences

Static components cost about 300 lines and need no JavaScript. Variants make
button and card styling consistent, and the token layer documents the palette's
roles and contrast pairs. Unlayered CSS in `app.css` and screen files still beats
Tailwind utilities. A component class that collides with screen CSS needs that CSS
removed, and tuning the global focus outline needs an important utility (such as
`focus-visible:outline-offset-2!`). Screen
selectors must not depend on styling classes. Upstream fixes are applied by hand.

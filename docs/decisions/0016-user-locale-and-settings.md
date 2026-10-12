# 0016. Per-account language preference and settings

Status: Implemented and deployed; visual and authenticated-device checks remain separate.

## Context

The interface needed English and Spanish, browser-language detection, and a choice shared across a user's devices.

## Decision

Identity stores a nullable `locale` preference. `nil` follows the browser; explicit values are `en` and `es`, validated by the domain and database. Only the verified actor's ID can update the preference.

Resolve locale in this order: account preference, `Accept-Language`, then Spanish. Normalize regional variants and honor quality, order, and exclusions. Set Gettext per request/process; the HTML document declares the effective language.

The authenticated `/settings` page initially contains the language selector. Saving reloads the full document so HTML and page text use the new locale. Other tabs and devices apply the preference on their next request or mount; there is no live cross-tab synchronization.

## Consequences

The setting is shared across devices without changing session semantics. Adding a language requires updating the domain value, persistence constraint, resolver, selector, and complete message catalogs. Automated translation coverage does not verify visual quality or device behavior.

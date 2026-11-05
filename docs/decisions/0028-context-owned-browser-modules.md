# 0028. Context-owned browser modules

Status: Implemented locally; integration pending.

## Context

Music and video already own their browser code, but a persistent Music session combined
authorization, queue navigation, media effects, state transitions and resource lifetime.
Video implementation was nested under its LiveView hook. Moving files alone would retain
the difficult dependency and state relationships.

## Decision

- Retain `music/`, `video/` and `shared/` context ownership. Hooks adapt LiveView lifecycle
  and screen events; player implementation lives beside the hooks under `player/`.
- Organize Music player responsibilities into `model/`, `operations/`, `adapters/` and
  `ui/`. Models contain browser-independent queue/selection rules and pure display-state
  transitions. Operations coordinate selection/authorization, navigation and listening
  activity using injected effects. Adapters wrap audio, HTTP, media events, cancellation
  and Media Session. UI modules receive snapshots and commands.
- Keep one session-owned playback/lifecycle record. Operations may update that shared
  record; they do not introduce another state owner. The session remains the public
  command facade and composes its internal dependencies. Bootstrap/runtime wire document
  services and the persistent host.
- Models import only models; operations import operations/models; adapters import
  adapters/models; UI imports UI/models. Effects and outward commands cross those
  boundaries through explicit dependencies. Verify the Music import graph in Node tests.
- Video uses source controllers, UI, recovery, diagnostics and timeline modules under
  `video/player/`. Retain direct/native-HLS fallback, source replacement, cleanup and
  stable fullscreen elements. Its simpler responsibilities do not require Music's exact
  layer structure.

## Consequences

The module tree makes responsibility and dependency direction visible. Selection and
queue changes can be reviewed without reading DOM rendering, while model rules can be
tested without media or network dependencies. More files and explicit dependency wiring
are accepted costs; coherent operations remain together rather than becoming one file
per trivial assignment.

This changes internal organization, not authorization or playback behavior. The existing
album retry-selection issue remains separate. Synthetic tests do not establish real-device
compatibility. Current rules live in the [frontend convention](../conventions/frontend.md).

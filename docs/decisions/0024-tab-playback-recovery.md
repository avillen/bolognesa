# 0024. Same-tab video playback recovery

Status: Implemented and deployed; target-device verification pending.

## Context

Recreating the playback page or hook selects the initial version and starts playback
again. A connection or browser-process failure can therefore return a long video to
the beginning without a media error reaching the server. Server-side connection-close
observations alone cannot distinguish these causes.

## Decision

Keep one best-effort checkpoint in `sessionStorage`, scoped to authenticated viewer,
content type/id and selected physical file. Save whole-file position and pause state
at most once every three seconds on time updates, and also on seeks, play/pause,
page lifecycle transitions and hook teardown. Ignore corrupt, mismatched or expired
checkpoints; expire after 12 hours and clear on completion. Storage failures must not
prevent playback. This is temporary same-tab recovery, not durable account progress
or cross-device synchronization. A different default version is not automatically
replaced with a previously selected version.

Direct playback restores after metadata loads. For HLS, the browser sends the matching
checkpoint as an optional `initial: {position_ms, paused}` hint beside the capability
report; clients without a checkpoint omit it. The server validates the whole envelope
(at most 8,192 external bytes, unknown report keys rejected), accepts the hint only for
the current checking generation, with exactly those two keys, an integer position in
0..2,147,483,647 below the known duration and a boolean pause flag, and otherwise starts
at offset zero with the default intent. The hint never names a file or attempt and does
not renew the recovery budget; preparation still reauthorizes the source and offset.
The selected plan is then prepared once at the accepted global offset with the
requested pause state, so no offset-zero producer is started and discarded. If the
prepared offset differs from the checkpoint, the browser records `restore_failed` and
plays what the server prepared. Ordinary session replacements do not reinstate the
original recovery checkpoint; preparation failures retain the existing visible
error/retry flow. Autoplay rejection is observed and leaves the normal play control
available.

Playback diagnostics add a per-document random UUID, navigation type, page lifecycle,
network availability, WebSocket close code/cleanliness, media readiness and a progress
sample every 30 seconds while playback is requested. Keep at most eight unacknowledged
observations in session storage for up to 12 hours and replay only for the same
viewer/content/file. Historical observations are explicitly marked and may reference
a previous transcode session; ordinary observations still require the current session.
All fields remain bounded and allowlisted at the server. Identifiers remain log-only;
raw transport reasons, browser error messages, URLs and user-agent strings are excluded.

## Consequences and limits

Episode and part navigation patches the existing LiveView. Keep the player frame and
ignored controls mounted while loading the next episode or handling a playback error;
replace only the media source. Errors stop the source without destroying the fullscreen
element, with an explicit retry inside element fullscreen. Checkpoints retain the
outgoing content scope when the same hook switches episodes. Full document reloads
cannot retain element fullscreen: browsers require a new user action to enter it.
Native mobile fullscreen remains a separate device-verification requirement.

Observation delivery is best effort. Replays can duplicate events when the server
received a message but its acknowledgement was lost. Abrupt process termination can
lose final events or storage entirely; a missing report never proves there was no
failure. A close code is a transport fact, not proof of which component caused a fault.
Client timestamps, page identifiers, availability and navigation type are diagnostic
hints and never authorization. Recovery mitigates losing position; it does not establish
or fix a particular browser crash.

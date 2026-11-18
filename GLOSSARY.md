# Glossary

Domain terms with a precise meaning in Bolognesa. Use them as defined in code, issues, and documentation.

## Playback

**Playback attempt**: one browser's try at playing a video file, from version selection until it is ready, fails, or ends. It owns the probe, delivery plan, temporary transcode session, and a single recovery to a compatible plan. Events that do not belong to the current attempt are ignored. _Avoid_: playback session (that is the server-side transcode session), playback state.

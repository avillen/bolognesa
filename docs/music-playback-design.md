# Music playback design

Status: Approved for planning. No music functionality is implemented by this document.

## Intended outcome

Add local music listening to Bolognesa iteratively. The complete journey is to scan a music library, browse artists and albums, play an album in track order, manage a queue, and keep listening while navigating the application. The first delivery makes individual songs discoverable and playable while establishing stable musical identities for later deliveries.

Use embedded file tags first and a filename fallback. External identification, artwork fetching, manual metadata editing, playlists, cross-device synchronization, and saved listening progress are deferred. Original files remain read-only. Existing movie and series journeys must continue working.

## Architecture assessment and prerequisite refactors

The existing contexts remain useful. A wholesale rewrite, generic media framework, and changes to movie/series identity are unnecessary. Make the following targeted refactors as part of the first delivery, with regression coverage before introducing music behavior:

1. **Library-aware discovery.** `FileDiscovery.walk/2` currently receives only a path and the local adapter filters a fixed video extension list. Pass a typed discovery request containing source path and library content type. A small explicit extension policy selects video candidates for movie/series libraries and audio candidates for music libraries. Preserve batching, source validation, scan generations, and complete-scan removal semantics.
2. **Inspection as a reusable source of observations.** Retain `Libraries` ownership of probing, revision checks, and technical observations. Add a bounded music-tag value object to the probe result and persistence mapping; request allowlisted tags from FFprobe. Preserve the existing output size and track limits. Include library content type in inspection inputs: the current `start_running/3` constructs a library without that field.
3. **Playback source selection separate from byte delivery.** Keep video entry selection intact and add a typed music-track source selector under `Playback`. Both selectors return the existing playback-owned `Source` model and use the same authorization and descriptor validation. Extract shared byte-response handling and the explicit MIME policy from the controller when adding the music endpoint. Do not generalize the video transcoder into an audio service for this delivery.
4. **Durable handoff after inspection.** Persist a music refresh outbox event in the transaction that accepts a successful current music inspection. Delivery invokes the public `Music` facade from a worker. This is a concrete additional event alongside the existing inspection-request flow, not a new generic event bus.

Defer application-wide layout restructuring until continuous navigation playback is implemented. The first delivery does not need a global player or queue infrastructure.

## Ownership and public boundaries

- `Libraries` owns music source configuration, inventory, recoverable scanning, technical inspection, and sanitized tag observations. Add `:music` to validated library types, persistence constraints, forms, and navigation.
- A new `Music` context owns local tracks, artists, albums, file associations, grouping policy, and musical read models. Use the project's domain/application/ports/infrastructure organization and global persistence schemas. Do not force local songs into `CatalogEntrySchema`, whose identity currently requires a TMDb provider and numeric resource ID.
- `Playback` owns authenticated selection of music sources and delivery. Its read adapter may join music associations with library inventory and current inspection, returning playback-owned models. `Music` does not serve bytes.
- `Identity` continues establishing the trusted actor. Authorize musical reads and playback in the backend, independently of page visibility.
- Web screens call public facades through screen-local reducers. No persistence schemas cross these interfaces.

Keep existing movie/episode facade contracts working. Use an explicit music entry point such as `Playback.start_track(actor, track_id, file_id)` so overlapping numeric IDs cannot select the wrong media kind. The controller endpoint is `/music/tracks/:track_id/media/:file_id` and exposes neither filesystem paths nor credentials.

## First-delivery data and grouping rules

Use stable database IDs rather than titles or paths in public track references. Initially each inventory file has one local track association, enforced by a unique file constraint. Rescans and metadata refresh update that track in place. Identical copies in different locations remain distinct tracks; audio fingerprinting and recording deduplication are deferred.

Allowlist title, artist, album artist, album, disc number, track number, and date/year. Normalize tag keys case-insensitively, trim values, require valid UTF-8, and bound each textual value to 512 bytes. Invalid or oversized individual tags become absent; they must not crash a job. Discard all other tags and embedded artwork. Track/disc numbers accept positive integers and `number/total` forms with a maximum of 9999; invalid numbers become absent. Accept a four-digit year or the leading year of an ISO date, bounded to 1000–9999.

- Title: embedded title, otherwise filename without extension. Render invalid filename bytes safely without changing the inventory's original path bytes.
- Track artist: embedded artist, otherwise absent. Render missing values as localized fallback labels rather than storing translated text.
- Album artist: embedded album artist, otherwise track artist.
- Artist identity: library ID plus normalized name; trim and case-fold names without dropping accents or punctuation. Treat multi-artist tag text as a single credited name in this delivery. Keep track artist distinct from album artist for compilation support.
- Album identity: library ID, source parent directory, normalized album title, and normalized album artist. This conservative local grouping avoids merging unrelated releases with the same title. Disc-subfolder consolidation and cross-library merging are deferred.
- A missing album tag leaves the track ungrouped; do not invent albums from folders or merge all unknown tracks into one album.
- Future album playback order is disc number, track number, then relative path and track ID. Missing numbers sort after known numbers. Preserve these fields in the first delivery.

Metadata changes may change artist/album membership but do not replace a track ID. Catalog queries count currently available associations; stale observations cannot overwrite current metadata. Historical grouping rows can remain without appearing as available albums/artists. No originals are modified.

## First-delivery flow and recovery

1. An administrator creates a music library and starts the existing durable scan.
2. Discovery accepts `.mp3`, `.m4a`, `.aac`, `.flac`, `.ogg`, `.opus`, and `.wav` candidates only for music libraries. Video libraries retain their existing extension list.
3. Inventory reconciles files and requests inspection. Music files do not request TMDb identification; enforce this at the downstream request boundary.
4. FFprobe runs outside transactions. Successful current observations persist technical properties and sanitized tags, together with a refresh event containing file ID and revision only.
5. A bounded, retryable music refresh worker reads the current observation through an explicit read port and atomically updates local musical records. Its adapter may join inventory and inspection tables but does not write them. Lock and recheck file revision, availability, and successful inspection inside the write transaction. Duplicate delivery is idempotent; late or missing-file events are harmless.
6. An outbox dispatcher recovers undispatched events after restart. Persist terminal music-import failure state by file and revision, expose it in the music screen, and offer an explicit retry that schedules refresh for a current successful inspection. Probe failures continue using the existing inspection retry/reinspection flow.
7. The music list loads asynchronously with bounded pagination, search, and library scope in URL parameters. It shows title, artist, album, duration, and a play action, plus distinct loading, empty, inspection/import failure, and read-error states. Pending inspection is visible as processing; files whose inspection fails cannot be played through an unchecked fallback.
8. Selecting a track checks the current successful audio inspection and source association. The music page presents an accessible native audio player with pause, seek, and volume controls. Each content request reauthorizes the session and revalidates the physical file.

Require an audio stream; attached artwork video streams alone do not establish video media. Do not feed music files into the existing video HLS profile. The first delivery uses direct audio with explicit extension/MIME mapping: MP3 `audio/mpeg`, M4A `audio/mp4`, AAC `audio/aac`, FLAC `audio/flac`, OGG `audio/ogg`, Opus `audio/ogg`, and WAV `audio/wav`. Discovery and a successful probe do not guarantee browser decoding. Show browser playback failures clearly; audio conversion remains future work.

Use current `GET`/`HEAD`, range, no-store, descriptor-closing, and empty unauthenticated response semantics. Reject mismatched track/file IDs, missing files, changed revisions, revoked sessions, unsafe paths, and stale associations. Logs contain IDs and bounded reasons rather than paths, musical titles, or tag dumps.

## Subsequent deliveries

### Artist and album browsing, then queue

Add library-scoped artist and album screens using the first delivery's identities and track ordering. Selecting an album creates an ordered queue of stable track/file references. Add previous/next, enqueue, remove, and automatic advance after an ended event. Represent duplicate queue entries with distinct queue-item IDs. A missing or failing item gives visible feedback and a bounded skip policy. Do not load an unbounded library to create a queue.

### Continuous playback during navigation

Move the audio element into a persistent authenticated application shell outside replaceable screen content. Use a focused browser controller for audio timing and queue transitions; LiveView provides authorized data and meaningful commands. Prove the element survives authenticated LiveView navigation before claiming continuity. A small layout experiment should settle the exact Phoenix lifecycle integration at that stage; preserving only queue data is insufficient.

The browser initially owns a per-tab temporary queue. Full reload, closing the tab, logout, or leaving the authenticated session ends it. Pause and clear on logout. Saved queues, reload recovery, and coordination between tabs/devices are separate features. Browser policy failures during automatic advance require a visible resume action.

## Acceptance and verification

The first delivery is complete when:

- A music library can be created and selected; movie/series libraries retain their behavior.
- Mixed-folder scans include only the candidate types for the selected library and never modify originals.
- Tagged and untagged supported audio files appear with the defined metadata/fallbacks, duration when known, and stable track IDs.
- Repeated scans, changed files, forced reinspection, duplicate jobs, stale completions, and restart recovery preserve the defined identity and revision guarantees.
- Inspection and import failures are visible and retryable through the appropriate flow. A partial scan cannot mark unseen files absent.
- Individual tracks can be played, paused, and sought through authenticated direct delivery with correct MIME and range responses.
- Unauthorized, mismatched, missing, unsafe, and changed-source requests are rejected with existing media response conventions.
- The interface has complete English/Spanish strings and usable keyboard/touch controls.
- Focused domain, PostgreSQL concurrency/outbox, LiveView, and controller regression tests pass, followed by `mix precommit`. Browser checks use synthetic audio and document actual formats tested; device compatibility and deployment require separate evidence.

No new runtime dependency is planned: use FFprobe and the existing job, persistence, and browser stack. Update product scope, roadmap, status, and durable backend/playback decisions when implementation is verified. This proposed design remains temporary working documentation and should be removed or distilled after delivery.

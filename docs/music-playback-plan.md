# Local Music Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the user selects delegated execution. Implement tasks in order and track the checkboxes below.

**Goal:** Scan a music library, import local tags into stable musical identities, and play individual songs through authenticated direct delivery.

**Architecture:** Keep inventory and observations in Libraries, add a Music context for musical records, and extend Playback with a separate track-source selector. Refactor discovery inputs and shared byte delivery without changing video behavior. A transactional outbox hands accepted music inspections to recoverable import jobs.

**Tech Stack:** Existing Elixir/Phoenix/LiveView, Ecto/PostgreSQL, Oban, FFprobe, Gettext, and native browser audio; no new runtime dependencies.

**Spec:** [Approved music playback design](music-playback-design.md).

**Status:** Saved for future implementation at the maintainer's request. No implementation tasks have started. Recheck current code, migrations, and baseline tests before execution; adjust this plan for intervening changes and confirm the execution method.

## Global constraints

- Original files remain read-only. Existing movie and series journeys must continue working.
- Use embedded file tags first and a filename fallback.
- Discard all other tags and embedded artwork.
- Normalize tag keys case-insensitively, trim values, require valid UTF-8, and bound each textual value to 512 bytes.
- Track/disc numbers accept positive integers and `number/total` forms with a maximum of 9999; invalid numbers become absent.
- Accept a four-digit year or the leading year of an ISO date, bounded to 1000–9999.
- External identification, artwork fetching, manual metadata editing, playlists, cross-device synchronization, and saved listening progress are deferred.
- No new runtime dependency is planned: use FFprobe and the existing job, persistence, and browser stack.
- Every new public function has a named, precise typespec; ports return domain models and facades return DTOs. Follow all conventions in `docs/conventions/`.
- Queue, album/artist screens, and continuous playback during navigation are subsequent deliveries, not acceptance criteria here.
- Preserve unrelated working-tree changes. Do not deploy, publish, merge, or claim device compatibility as part of this plan.

## Review focus

1. Forced reinspection at the same file revision can change tags: import must use the current successful inspection token, not just a revision comparison. Covered in Tasks 4–5.
2. Music tags must not accidentally retain private video titles: default video parsing still discards title/artist tags. Covered in Task 2.
3. Two albums with the same title and absent album artist must not merge across folders or libraries, and concurrent writes must not create duplicates. Covered in Tasks 3–4.
4. Literal `%` and `_` in musical searches must not become SQL wildcards, and stale responses must not replace a newer search. Covered in Tasks 6–7.
5. Audio playback failures, source changes, and revoked sessions must be visible or rejected, including when IDs overlap existing movie entries. Covered in Tasks 6–7.

## Execution preparation

- [ ] Read the spec, `AGENTS.md`, product/status/roadmap, decision index, and the backend, frontend, Elixir, Phoenix, testing, observability, documentation, and commit conventions.
- [ ] Inspect `git status --short` and create an isolated working branch/worktree at execution time using `superpowers:using-git-worktrees`. Carry only the approved music documents if they are uncommitted; leave unrelated captures/CI/contributor changes alone.
- [ ] Run `mix precommit` as a baseline, record its actual outcome, and distinguish existing failures from music regressions. Use the project's existing PostgreSQL setup; do not reset shared databases.
- [ ] For every task below, run the specified failing scenario before implementation and the focused suite afterward. Inspect the staged patch and commit metadata before each focused commit. Task commits include only music work.

## Task 1: Refactor discovery and byte delivery while preserving video behavior

**Files**

- Create `lib/bolognesa/libraries/domain/value_objects/files/discovery_request.ex` and `lib/bolognesa/libraries/domain/policies/media_extensions.ex`.
- Modify `lib/bolognesa/libraries/application/ports/services/file_discovery.ex`, `lib/bolognesa/libraries/application/use_cases/discover_files.ex`, and `lib/bolognesa/libraries/infrastructure/services/local_file_discovery.ex`.
- Modify `test/support/libraries/controlled_file_discovery.ex` and discovery call sites located by `rg 'LocalFileDiscovery.walk|discovery.walk' lib test`.
- Create `lib/bolognesa_web/controllers/media_delivery.ex` and `lib/bolognesa_web/controllers/media_mime.ex`; modify `lib/bolognesa_web/controllers/media_controller.ex`.
- Test `test/bolognesa/libraries/discover_files_test.exs`, `test/bolognesa/libraries/local_file_discovery_test.exs`, `test/bolognesa_web/controllers/media_controller_test.exs`, and `test/bolognesa_web/controllers/episode_transcode_controller_test.exs`.

**Interfaces**

```elixir
# DiscoveryRequest owns %{path: String.t(), content_type: Library.content_type()}.
DiscoveryRequest.new(%Library{}) # {:ok, DiscoveryRequest.t()} | {:error, :invalid_request}
MediaExtensions.for_type(:movie) # existing video extensions; :series has the same list
# FileDiscovery callback changes its first argument, preserving sink/error types:
@callback walk(DiscoveryRequest.t(), sink()) :: :ok | {:error, error()}
MediaMime.for_path(relative_path) # {:ok, String.t()} | {:error, :unsupported}
MediaDelivery.serve(conn, source, mime_type) # Plug.Conn.t(); owns open/close and response
```

- [ ] Add a discovery test proving content type reaches the adapter and mixed movie folders still exclude audio. Update existing filesystem tests to pass a typed request without weakening replacement, symlink, unreadable-entry, or batch assertions.

```elixir
test "movie discovery ignores audio without modifying source bytes", %{path: path} do
  File.write!(Path.join(path, "film.MP4"), "video")
  File.write!(Path.join(path, "song.mp3"), "audio")
  {:ok, request} = DiscoveryRequest.new(%Library{path: path, content_type: :movie})
  assert :ok = LocalFileDiscovery.walk(request, capture_sink())
  assert_receive {:entries, [entry]}
  assert entry.relative_path == "film.MP4"
  assert File.read!(Path.join(path, "song.mp3")) == "audio"
end
```

- [ ] Run `mix test test/bolognesa/libraries/local_file_discovery_test.exs test/bolognesa/libraries/discover_files_test.exs`; verify the new typed contract fails before implementation.
- [ ] Construct the request from the full library returned by `begin_attempt/2`, carry it through discovery, and move the existing video extension list into the policy. Keep physical-path validation unchanged.
- [ ] Extract byte delivery into `MediaDelivery` and MIME lookup into `MediaMime`. The controller still calls `Playback.start/3`; shared delivery opens the descriptor, validates ranges, closes it with `try/after`, and returns the existing statuses. No audio mappings yet.

```elixir
with {:ok, source} <- Playback.start(actor, entry_id, file_id),
     {:ok, mime} <- MediaMime.for_path(source.relative_path) do
  MediaDelivery.serve(conn, source, mime)
else
  {:error, reason} -> MediaDelivery.error_response(conn, reason)
end
```

- [ ] Run both focused discovery suites and `mix test test/bolognesa_web/controllers/media_controller_test.exs test/bolognesa_web/controllers/episode_transcode_controller_test.exs`. Verify full/partial responses, HEAD, malformed/unsatisfiable ranges, missing sources, and unauthorized requests remain covered.
- [ ] Commit the verified refactor as `refactor(media): separate discovery policy and byte delivery`.

## Task 2: Add music library inventory and bounded tag observations

**Files**

- Create migration `priv/repo/migrations/20261012150000_add_music_library_inspection.exs`.
- Modify `lib/bolognesa/libraries/domain/entities/library.ex`, `lib/bolognesa/libraries/domain/value_objects/files/new_library.ex`, `lib/bolognesa/infrastructure/persistence/library_schema.ex`, and Task 1's extension policy.
- Create `lib/bolognesa/libraries/domain/value_objects/inspection/music_tags.ex`.
- Modify `lib/bolognesa/libraries/domain/value_objects/inspection/technical_media.ex`, `lib/bolognesa/libraries/domain/entities/inspection.ex`, `lib/bolognesa/infrastructure/persistence/inspection_schema.ex`, `lib/bolognesa/libraries/infrastructure/repositories/ecto_inspection_repository.ex`, its `inspection_mapper.ex`, and `lib/bolognesa/libraries/infrastructure/repositories/ecto_scan_repository.ex`.
- Modify `lib/bolognesa/libraries/infrastructure/services/ffprobe_json.ex` and `ffprobe_media_probe.ex`.
- Test/create `test/bolognesa/libraries/music_tags_test.exs`; update `library_test.exs`, `local_file_discovery_test.exs`, `ffprobe_json_test.exs`, `ffprobe_media_probe_test.exs`, `inspection_pipeline_test.exs`, and `scan_inventory_test.exs` in that directory.

**Interfaces**

```elixir
# Add :music to Library.content_type().
MusicTags.from_raw(raw_tags) # MusicTags.t(), with bounded strings/numbers or nil
# Fields: title, artist, album_artist, album, disc_number, track_number, year.
# TechnicalMedia and Inspection gain music_tags: MusicTags.t() | nil.
FfprobeJson.parse(output, content_type \\ :movie) # preserves existing one-argument calls
MediaExtensions.for_type(:music) # ~w(.mp3 .m4a .aac .flac .ogg .opus .wav)
```

- [ ] Add domain tests for tag normalization and a parser regression ensuring video tags remain discarded.

```elixir
test "bounds tag values and parses musical numbering" do
  tags = MusicTags.from_raw(%{
    "TITLE" => "  Sample Song  ", "track" => "3/12", "disc" => "2/2",
    "artist" => String.duplicate("x", 513), "date" => "2024-04-03",
    "comment" => "discard me"
  })
  assert tags.title == "Sample Song"
  assert tags.track_number == 3
  assert tags.disc_number == 2
  assert tags.artist == nil
  assert tags.year == 2024
  refute Map.has_key?(Map.from_struct(tags), :comment)
end
```

- [ ] Add tests for empty tags, non-map tags, unknown keys, case aliases (`album_artist`/`albumartist`, `track`/`tracknumber`, `disc`/`discnumber`), malformed and oversized numbers, invalid UTF-8, and an audio file with an attached picture. Missing/invalid tags become absent; malformed technical JSON remains an inspection failure.
- [ ] Add an inventory test proving music creates inspection requests and zero identification decisions/jobs/outbox events. Add an extension test with uppercase audio candidates and an ignored MP4. Run the affected tests; verify expected failures.
- [ ] Extend the library enum and replace `libraries_content_type_valid` with a three-type constraint. Add `media_inspections.music_tags` as nullable map; keep old video observations compatible. Refuse migration rollback while music libraries exist rather than deleting data.
- [ ] Normalize tags only for `:music`; keep default parser behavior for video. FFprobe adds allowlisted format tags for music only, passes the actual library type into parsing, and retains 30-second/262144-byte/128-track bounds.

```elixir
# Music observation must contain audio, even if there is an artwork video stream.
defp audio_present?(tracks), do: Enum.any?(tracks, &(&1.kind == :audio))
# Build an inspection input with LibraryMapper.to_library(library), not a partial struct.
# In request_inspection!, reset music_tags: nil along with prior technical fields.
```

- [ ] Skip TMDb scheduling at `EctoScanRepository.schedule_identifications` for music, using the library type from the current scan's persisted library. Keep movie/series request behavior unchanged; do not invoke another context's use cases.
- [ ] Run `mix test test/bolognesa/libraries`. Confirm rescan/removal/generation and video privacy tests pass.
- [ ] Commit as `feat(libraries): inspect music sources and local tags`.

## Task 3: Define musical identities and persistence guarantees

**Files**

- Create migration `priv/repo/migrations/20261012150100_create_music_records.exs`.
- Create `lib/bolognesa/music/domain/entities/{track,artist,album,import_state}.ex` and `lib/bolognesa/music/domain/value_objects/{observation,track_metadata}.ex` (each brace entry is a separate file).
- Create `lib/bolognesa/music/domain/policies/grouping.ex`.
- Create `lib/bolognesa/infrastructure/persistence/music_{track,artist,album,import}_schema.ex` (four separate files).
- Create `test/bolognesa/music/grouping_test.exs`, `test/bolognesa/music/persistence_test.exs`, and `test/support/music_fixtures.ex`.

**Interfaces and storage**

```elixir
TrackMetadata.from_observation(observation) # TrackMetadata.t(); applies fallback/grouping
Grouping.artist_key(name) # normalized String.t() | nil
Grouping.album_key(library_id, parent_bytes, album, album_artist)
# nil when album is absent; otherwise a tuple, not a concatenated string
# Observation fields: file_id, library_id, revision, inspection_token,
# relative_path (binary), duration_ms, music_tags (typed sanitized observations).
```

Tables:

- `music_artists`: library FK, display name, normalized name; unique `(library_id, normalized_name)`.
- `music_albums`: library FK, source parent `bytea`, title, normalized title, nullable artist FK, normalized album-artist name with non-null empty-string sentinel for absent artist, nullable year. Unique `(library_id, source_parent, normalized_title, album_artist_key)`.
- `music_tracks`: unique media-file FK, library FK, title, nullable track-artist/album FKs, disc/track number, nullable year, observed revision and inspection UUID token. Check positive revision and numbers within 1–9999. Track ID stays unchanged when metadata changes.
- `music_imports`: unique media-file FK, observed revision/token, pending/running/succeeded/failed state, job ID, bounded failure reason, start/finish timestamps. Music owns this state. No file availability duplication.

Use restrictive FKs for musical references and original inventory. Availability comes from inventory. Optional album/artist rows have no translated unknown labels. File path bytes remain in inventory and album grouping only; public DTOs do not expose paths.

- [ ] Add pure grouping tests before implementation.

```elixir
test "folder and library boundaries separate otherwise identical albums" do
  first = Grouping.album_key(1, "a", " Sample Album ", nil)
  assert first == Grouping.album_key(1, "a", "sample album", nil)
  refute first == Grouping.album_key(1, "b", "sample album", nil)
  refute first == Grouping.album_key(2, "a", "sample album", nil)
  assert nil == Grouping.album_key(1, "a", nil, "Sample Artist")
end
```

- [ ] Add tests for compilation album artist differing from track artist, punctuation/accents retained, blank tags, invalid filename-byte replacement in title, ungrouped tracks, and disc/track values retained for later ordering. Run `mix test test/bolognesa/music/grouping_test.exs`; confirm failure for missing modules.
- [ ] Implement pure domain values and schemas. Derive source parent via binary path splitting so invalid UTF-8 bytes do not break grouping. Use a UTF-8-safe display conversion for fallback title; do not rewrite raw path bytes.
- [ ] Add PostgreSQL tests proving unique file association, unique artist/album grouping with missing artist, FK protection, and numeric checks. Exercise competing upserts using supervised tasks with separate SQL connections and deterministic barriers, not sleeps.
- [ ] Implement `Bolognesa.MusicFixtures.music_fixture/1`: create a music library, inventory file, and current audio inspection; return a map with `actor`, `library`, `file`, and `inspection` keys. `actor` is a domain administrator, and the other values are inserted persistence records used only in tests. Fixture keyword options accept `tags`, `relative_path`, `availability`, `revision`, and `inspection_state` (default `:succeeded`). Build sanitized tags through `MusicTags.from_raw/1`. Physical files are created only for media controller tests under configured temporary roots. Add `refresh_fixture/1` in Task 4 after its facade exists.
- [ ] Run `mix test test/bolognesa/music/grouping_test.exs test/bolognesa/music/persistence_test.exs`; commit as `feat(music): establish local track artist and album identities`.

## Task 4: Import current observations atomically through Music

**Files**

- Create `lib/bolognesa/music.ex`.
- Create `lib/bolognesa/music/application/use_cases/refresh_track.ex`, `application/ports/readers/observations_reader.ex`, and `application/ports/repositories/music_repository.ex` under that context.
- Create `lib/bolognesa/music/infrastructure/readers/ecto_observations_reader.ex` and `infrastructure/repositories/ecto_music_repository.ex`, with a `music_mapper.ex` beside the repository.
- Create `test/bolognesa/music/refresh_track_test.exs` and `test/bolognesa/music/import_concurrency_test.exs`.

**Interfaces**

```elixir
Music.refresh_track(file_id, revision) # system facade; :ok | {:error, :unavailable}
# Reader returns {:ok, Observation.t()} | {:ok, :stale} | {:error, :unavailable}.
ObservationsReader.current(file_id, revision)
# Repository rechecks before writes, returning domain Track or harmless stale result.
MusicRepository.apply_observation(observation, metadata)
# {:ok, Track.t()} | {:ok, :stale} | {:error, :unavailable}
```

- [ ] Write an idempotency/identity test using Task 3's fixture, then run it to establish failure.

```elixir
test "duplicate refresh preserves the track identity" do
  fixture = music_fixture(tags: %{"title" => "Sample Song"})
  assert :ok = Music.refresh_track(fixture.file.id, fixture.file.revision)
  first = Repo.get_by!(MusicTrackSchema, media_file_id: fixture.file.id)
  assert :ok = Music.refresh_track(fixture.file.id, fixture.file.revision)
  second = Repo.get_by!(MusicTrackSchema, media_file_id: fixture.file.id)
  assert first.id == second.id
end
```

- [ ] Read sanitized observations outside the write transaction. The application builds `TrackMetadata`; the repository owns persistence mapping and transaction mechanics. No FFprobe, filesystem, or provider calls occur in a transaction.
- [ ] Add `Bolognesa.MusicFixtures.refresh_fixture/1`: call `music_fixture/1`, assert successful `Music.refresh_track/2`, fetch `MusicTrackSchema` by media file ID, and add it under the `track` key. Import this helper explicitly in tests that use it.
- [ ] Implement the atomic repository path: lock inventory file, then inspection, then import state in that order; recheck music library, availability, file revision, successful inspection revision/token, and audio presence. Lock-only reads do not transfer inventory ownership. Return stale without writing on mismatch.

```elixir
case reader.current(file_id, revision) do
  {:ok, :stale} -> :ok
  {:ok, observation} -> apply_current(observation, repository)
  {:error, :unavailable} -> {:error, :unavailable}
end

defp apply_current(observation, repository) do
  metadata = TrackMetadata.from_observation(observation)
  case repository.apply_observation(observation, metadata) do
    {:ok, _track_or_stale} -> :ok
    {:error, :unavailable} -> {:error, :unavailable}
  end
end
```

- [ ] Upsert artist/album rows with the database unique keys, then upsert the track on media file ID, preserving its ID. Store the accepted token/revision and mark its import successful atomically. Use `log: false` for tag/title/path SQL.
- [ ] Add race tests where revision or successful inspection token changes between reader return and repository write, including same-revision forced reinspection. Old metadata must not win. Also cover a file becoming missing and two concurrent imports of songs sharing an album; assert one grouping row.
- [ ] Run `mix test test/bolognesa/music`; commit as `feat(music): refresh tracks from current observations atomically`.

## Task 5: Deliver inspection refreshes with durable recovery and retry

**Files**

- Create migration `priv/repo/migrations/20261012150200_create_music_refresh_events.exs`.
- Create `lib/bolognesa/infrastructure/persistence/music_refresh_event_schema.ex`.
- Modify `lib/bolognesa/libraries/infrastructure/repositories/ecto_inspection_repository.ex`.
- Create `lib/bolognesa/libraries/application/ports/repositories/music_refresh_outbox_repository.ex`, `infrastructure/repositories/ecto_music_refresh_outbox_repository.ex`, and `infrastructure/jobs/music_refresh_dispatcher.ex` under Libraries.
- Create `lib/bolognesa/music/application/use_cases/retry_import.ex`, `application/ports/repositories/import_repository.ex`, `infrastructure/repositories/ecto_import_repository.ex`, and `infrastructure/jobs/{refresh_worker,import_policy,import_reconciler}.ex` under Music.
- Modify `lib/bolognesa/music.ex`, `lib/bolognesa/application.ex`, and `config/{config,test,screenshots}.exs`.
- Create `test/bolognesa/music/import_recovery_test.exs` and `test/bolognesa/libraries/music_refresh_outbox_test.exs`; update `inspection_pipeline_test.exs`.

**Interfaces and policy**

```elixir
Music.retry_import(actor, file_id) # :ok | {:error, :forbidden | :not_found | :unavailable}
MusicRefreshOutboxRepository.dispatch_batch(limit) # {:ok, non_neg_integer()} | {:error, :unavailable}
ImportRepository.request_retry(file_id) # same current-successful-observation validation
ImportRepository.begin_attempt(file_id, revision, job_id)
# {:ok, ImportState.t()} | {:ok, :stale} | {:error, :unavailable}
ImportRepository.fail_attempt(file_id, revision, inspection_token, reason)
# :ok | {:ok, :stale} | {:error, :unavailable}
ImportRepository.reconcile_jobs(now) # :ok | {:error, :unavailable}
```

Policy: three Oban attempts, queue `music_imports` with concurrency 1, dispatcher batch 100 every 5 seconds plus startup dispatch, reconciler batches 100 every 30 seconds and rescues executing imports older than 60 seconds only when their associated job is also stale. Failure reasons: `storage_unavailable`, `attempts_exhausted`, `unexpected_failure`. These are operational budgets, not playback compatibility promises.

- [ ] Test completion creates an event only when the current music inspection is accepted, and obsolete completion creates none. Event rows store file ID, revision, inspection token for uniqueness, delivered timestamp; job payload contains only file ID and revision. Every successful token gets one event, including same-revision reinspection. The worker always reads the latest successful token.

```elixir
test "refresh jobs expose only internal references" do
  fixture = music_fixture(inspection_state: :running)
  {:ok, media} = TechnicalMedia.new(%{
    format: "mp3", duration_ms: 2_500,
    tracks: [%{kind: :audio, codec: "mp3"}],
    music_tags: MusicTags.from_raw(%{"title" => "Sample Song"})
  })
  assert :ok = EctoInspectionRepository.complete_inspection(
    fixture.file.id, fixture.inspection.token, media)
  assert {:ok, 1} = EctoMusicRefreshOutboxRepository.dispatch_batch(100)
  assert [%Oban.Job{args: args}] = all_enqueued(queue: "music_imports")
  assert args == %{"file_id" => fixture.file.id, "revision" => fixture.file.revision}
end
```

- [ ] Run `mix test test/bolognesa/libraries/music_refresh_outbox_test.exs`; confirm failure before adding event insertion and dispatch.
- [ ] Insert refresh event in the same transaction as accepted music inspection completion. Dispatch with `FOR UPDATE SKIP LOCKED`; insert job and mark event delivered atomically, as the existing inspection outbox does. Libraries owns these event writes; Music's retry writes its own import/job state and does not write a Libraries-owned event.
- [ ] Add a worker that starts a token-specific import attempt, calls `Music.refresh_track/2`, and records transient/terminal failures only if its job/token remains current. An unavailable database remains a retryable error; if final failure cannot be stored, the reconciler restores visible terminal state when storage recovers. A stale/duplicate job cannot downgrade a successful current import.
- [ ] Add recovery tests for stopped dispatcher startup, failed job insertion rollback, concurrent dispatchers, duplicate jobs, lost/discarded/cancelled jobs, same-revision stale workers, terminal feedback, and authorized explicit retry. Use the repository's existing committed-test pattern for actual concurrency; clean all created rows with `try/after`.
- [ ] Register dispatch/reconciliation children and flags; disable both in test/screenshots configuration and add the production queue. Do not change global runtime configuration from tests.
- [ ] Run `mix test test/bolognesa/music test/bolognesa/libraries/music_refresh_outbox_test.exs test/bolognesa/libraries/inspection_pipeline_test.exs`; commit as `feat(music): recover inspection imports and retries`.

## Task 6: Add bounded music reads and authenticated audio delivery

**Files**

- Create `lib/bolognesa/music/domain/read_models/{track_row,track_page}.ex` and `application/dto/{track,track_page}.ex` under Music.
- Create `lib/bolognesa/music/application/ports/readers/tracks_reader.ex`, `application/use_cases/list_tracks.ex`, and `infrastructure/readers/ecto_tracks_reader.ex`; modify `lib/bolognesa/music.ex`.
- Create `lib/bolognesa/playback/application/use_cases/start_track_playback.ex`; modify `lib/bolognesa/playback.ex`, its `application/ports/repositories/playback_repository.ex`, and `infrastructure/repositories/ecto_playback_repository.ex`.
- Create `lib/bolognesa_web/controllers/music_media_controller.ex`; modify `lib/bolognesa_web/router.ex` and `controllers/media_mime.ex`.
- Create `test/bolognesa/music/list_tracks_test.exs`, `test/bolognesa/playback/start_track_playback_test.exs`, and `test/bolognesa_web/controllers/music_media_controller_test.exs`.

**Interfaces**

```elixir
Music.list_tracks(actor, query, page, library_id)
# {:ok, Music.Application.Dto.TrackPage.t()}
# | {:error, :forbidden | :invalid_query | :not_found | :unavailable}
TracksReader.list_tracks(query, page, library_id)
# {:ok, Domain.ReadModels.TrackPage.t()} | {:error, :not_found | :unavailable}
Playback.start_track(actor, track_id, file_id)
# {:ok, Source.t()} | {:error, :forbidden | :not_found | :missing | :unavailable}
PlaybackRepository.find_track_source(track_id, file_id) # same source/error result
```

Read contract: page size 50, page 1–100000, UTF-8 query at most 256 bytes, optional nil library selects all music libraries. A selected existing non-music library is rejected. Join inventory to tracks/inspection/imports so pending and failed files without a track still appear. A `TrackRow` has `file_id`, optional `id` (track ID), title, optional artist/album/duration, processing state (`:pending`, `:ready`, `:inspection_failed`, `:import_failed`), and bounded failure reason. DTOs preserve these fields, exclude raw paths/tokens, and use `TrackPage` fields `items`, `total`, `page`, and `page_size`. Render time determines fallback labels. Only ready rows are playable.

- [ ] Add read tests for authorization, library isolation, empty libraries, available-only results, no-track pending/failed files, changed revisions, bounded pagination, and search over title/artist/album with literal wildcard characters.

```elixir
test "music list requires authorization" do
  assert {:error, :forbidden} = Music.list_tracks(nil, "", 1, nil)
end

test "track and file identity must match" do
  first = refresh_fixture(tags: %{"title" => "First"})
  second = refresh_fixture(tags: %{"title" => "Second"})
  assert {:ok, %Source{}} = Playback.start_track(first.actor, first.track.id, first.file.id)
  assert {:error, :not_found} =
           Playback.start_track(first.actor, first.track.id, second.file.id)
end
```

- [ ] Run `mix test test/bolognesa/music/list_tracks_test.exs test/bolognesa/playback/start_track_playback_test.exs`; verify the expected failures.
- [ ] Implement authorized use cases and database reader with explicit bounded selects and `log: false`. Stable list order is display title then file ID. Escape `\\`, `%`, and `_` before parameterized `ILIKE` queries.
- [ ] Implement the track selector using the track/file relation plus successful current audio inspection, current imported token/revision, and music library type. Preserve video selectors. Return missing for a matched unavailable file; return not-found for invalid, unimported, stale, non-audio, or mismatched relationships.
- [ ] Add the music endpoint in the existing media pipeline, invoke the new selector and Task 1's shared delivery, and add the seven audio MIME mappings from the spec.
- [ ] Test GET, HEAD, 206 seeking bytes, 400/416 ranges, no-store, session revocation/401, ID overlap with video, source revision/path replacement, and unsupported extensions. Use generated synthetic audio/controlled temporary bytes; ordinary controller tests do not require a browser decoder.
- [ ] Run `mix test test/bolognesa/music/list_tracks_test.exs test/bolognesa/playback test/bolognesa_web/controllers`; commit as `feat(playback): serve authorized music tracks`.

## Task 7: Expose music library setup and individual listening

**Files**

- Create `lib/bolognesa_web/live/music/index/live.ex`, `live.html.heex`, `forms/filters.ex`, and `state/track.ex`.
- Create `lib/bolognesa_web/live/music/index/reducer/{load,apply_page,play,retry_import}.ex`.
- Modify `lib/bolognesa_web/router.ex`, `library_navigation.ex`, `components/layouts.ex`, and `live/library/index/forms/library.ex`, `state/library.ex`, `live.html.heex`.
- Create `assets/js/hooks/audio_error.js`; modify `assets/js/app.js` and `assets/css/app.css` only for concrete screen needs.
- Update `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, and `priv/gettext/es/LC_MESSAGES/default.po`.
- Create `test/bolognesa_web/live/music/index/live_test.exs`; update `library_navigation_test.exs`, `live/library/index/live_test.exs`, `translations_test.exs`, and `interface_language_test.exs` under `test/bolognesa_web/`.

**Interfaces**

```elixir
Load.call(socket, query, page) # socket; starts {:music_tracks, request_id} async read
ApplyPage.call(socket, request_id, result) # socket; drops stale IDs
Play.call(socket, track_id, file_id) # socket; authorizes selection through Playback
RetryImport.call(socket, file_id) # socket; calls Music.retry_import/2 and reloads
```

- [ ] Add tests for creating a music library, immediate sidebar navigation to `/music?library_id=...`, and invalid cross-type selection. Add a tagged/untagged list test and play selection test using Task 3's fixture.

```elixir
test "a selected track renders authenticated native audio", %{conn: conn, token: token} do
  fixture = refresh_fixture(tags: %{"title" => "Sample Song"})
  {:ok, view, _html} = live(init_test_session(conn, user_token: token),
    "/music?library_id=#{fixture.library.id}")
  render_async(view)
  view |> element("#play-track-#{fixture.track.id}") |> render_click()
  assert has_element?(view, "audio#music-player[controls]")
  assert has_element?(view,
    "audio#music-player source[src='/music/tracks/#{fixture.track.id}/media/#{fixture.file.id}']")
end
```

Use the existing web setup pattern: call `Identity.install_admin/1` with synthetic `music@example.com` credentials, then `Identity.start_session/2` and return its token in the test context. All administrators currently share media access; the domain actor used by backend fixtures need not be the signed-in account's ID.

- [ ] Run `mix test test/bolognesa_web/live/music/index/live_test.exs test/bolognesa_web/library_navigation_test.exs`; verify the music route/screen failures.
- [ ] Add the route to the authenticated live session. Add explicit music sidebar path, icon, form option, and library type label. Preserve stored names and empty-library navigation.
- [ ] Implement async list/search with URL state, a monotonically unique request reference, stream IDs based on file ID, total/page controls, processing and retry feedback, and retained results on failed refresh. Present loading, empty, read-error, inspection failure, and import failure separately. Probe failures link to library reinspection; import failures get authorized per-file retry.
- [ ] Render an accessible native player after selection without autoplay. Play action selects the source; the native play control begins listening. The audio error hook reports a bounded error event, updates visible feedback via the LiveView, and removes listeners on destruction. Do not repeatedly set `src` during unrelated list refreshes.

```javascript
export default {
  mounted() {
    this.onAudioError = () => this.pushEvent("audio-error", {})
    this.el.addEventListener("error", this.onAudioError)
  },
  destroyed() {
    this.el.removeEventListener("error", this.onAudioError)
  }
}
```

- [ ] Add scenarios for stale search results, literal query characters, backend unavailable, source changed between listing and click, retry denied, and browser error feedback. Test mobile-friendly control layout and keyboard focus during manual browser verification, not through invented DOM-only compatibility claims.
- [ ] Extract Gettext messages and complete English/Spanish catalogs. Keep unknown artist/album placeholders in presentation only; catalog data stays untranslated. Run `mix test test/bolognesa_web/live/music test/bolognesa_web/live/library test/bolognesa_web/library_navigation_test.exs test/bolognesa_web/translations_test.exs test/bolognesa_web/interface_language_test.exs` and `mix assets.build`.
- [ ] Commit as `feat(web): browse and play individual music tracks`.

## Task 8: Verify the complete journey and update durable project guidance

**Files**

- Create `test/bolognesa/music/music_journey_test.exs` only for the uncovered end-to-end backend journey, plus `test/support/libraries/successful_music_probe.ex` as its controlled FFprobe boundary.
- Update `docs/product.md`, `docs/roadmap.md`, `docs/status.md`, `docs/conventions/backend.md`, `docs/decisions/0006-authorized-direct-playback.md`, and `docs/decisions/README.md`.
- Create `docs/decisions/0018-local-music-catalog.md` for the accepted separate Music identity/ownership and durable handoff. Do not rewrite earlier decisions to imply they originally covered music.
- Remove the temporary music design and plan after successful completion, distilling lasting choices into the decision and current conventions. Preserve explicit unresolved verification limits in status.

- [ ] Write the backend journey using a synthetic temporary music directory: create library, scan, dispatch inspection jobs, accept controlled successful tags, dispatch refresh, verify stable track identity after rescan, then select a source for playback. Do not duplicate all lower-layer failure tests.

```elixir
test "a scanned music file becomes a playable stable local track" do
  root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
  path = Path.join(root, "music-journey-#{System.unique_integer([:positive])}")
  File.mkdir_p!(path)
  on_exit(fn -> File.rm_rf!(path) end)
  File.write!(Path.join(path, "sample.mp3"), "controlled audio")
  actor = %Actor{id: 1, role: :admin}
  {:ok, library} = Libraries.create_library(actor,
    %{name: "Sample music", path: path, content_type: :music})
  assert {:ok, _scan} = Libraries.start_scan(actor, library.id)
  assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
  assert {:ok, 1} = EctoOutboxRepository.dispatch_batch(100)
  inspection = Repo.get_by!(InspectionSchema,
    media_file_id: Repo.one!(MediaFileSchema).id)
  job = Repo.get!(Oban.Job, inspection.job_id)
  assert :ok = InspectionWorker.perform(%{job | attempt: 1},
    EctoInspectionRepository, SuccessfulMusicProbe)
  assert {:ok, 1} = EctoMusicRefreshOutboxRepository.dispatch_batch(100)
  assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :music_imports)
  assert {:ok, %{items: [track]}} = Music.list_tracks(actor, "Sample", 1, library.id)
  assert {:ok, %Source{relative_path: "sample.mp3"}} =
    Playback.start_track(actor, track.id, track.file_id)
  assert {:ok, _scan} = Libraries.start_scan(actor, library.id)
  assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
  assert {:ok, %{items: [again]}} = Music.list_tracks(actor, "Sample", 1, library.id)
  assert again.id == track.id
  assert File.read!(Path.join(path, "sample.mp3")) == "controlled audio"
end
```

- [ ] Implement the controlled probe's `MediaProbe.inspect/2` callback with `TechnicalMedia.new/1`, `format: "mp3"`, `duration_ms: 2500`, one MP3 audio track, and `MusicTags.from_raw(%{"title" => "Sample Song"})`. Run `mix test test/bolognesa/music/music_journey_test.exs` until the complete journey passes.
- [ ] Run `mix precommit` and resolve failures introduced by this work. Run `mix assets.build` if browser assets changed after Task 7. Run `git diff --check` and verify all local Markdown links touched by the change.
- [ ] Use the available browser-control skill to exercise a synthetic MP3 in the local app: select a track, play/pause, seek, refresh results, and observe error feedback. Record browser and actual format tested. If browser access is unavailable, record that explicitly; automated response tests establish delivery but not decoding.
- [ ] Review migrations for upgrade on existing movie/series data and safe rollback refusal. Review the branch against the approved spec using `superpowers:requesting-code-review`; fix concrete findings and rerun affected checks. A delegated final review is permitted by that skill; no per-task delegation unless selected by the user.
- [ ] Update product scope to describe implemented individual music listening; put artist/album browsing, queue, and continuous navigation playback in the roadmap with separate acceptance outcomes. Update status with actual test counts, browser evidence, unverified formats/devices, and the next delivery. Do not claim a deployment.
- [ ] Commit as `docs(music): record verified local listening and next deliveries`. Use `superpowers:finishing-a-development-branch` for the final branch handoff; integration actions follow the user's authorization.

## Plan review and handoff

This plan implements the first delivery only. The subsequent artist/album/queue and persistent-shell work need their own focused implementation plans after real use of this base. Recommended execution is native in this session: the tasks share inventory revisions, observation tokens, and source contracts, so one implementer can carry those interfaces consistently and request a whole-branch review at the end.

Implementation starts after the user reviews this plan and selects native or delegated execution. No task above is marked complete by writing this document.

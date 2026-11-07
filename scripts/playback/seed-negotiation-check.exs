# Extend a dedicated native demo database with actual inspected synthetic fixtures.
# Run after verify-negotiated-output.exs and scripts/dev/demo-setup.sh.
alias Bolognesa.Repo
alias Bolognesa.Libraries.Infrastructure.Services.FfprobeJson

alias Bolognesa.Infrastructure.Persistence.{
  EpisodeSchema,
  InspectionSchema,
  LibrarySchema,
  MediaFileSchema,
  MovieIdentificationSchema,
  SeriesIdentificationSchema,
  SeriesIdentificationEpisodeSchema
}

unless String.starts_with?(System.fetch_env!("BOLOGNESA_DB_NAME"), "bolognesa_demo_") do
  raise "Requires a disposable demo database"
end

[directory, ids_path] = System.argv()
ids = ids_path |> File.read!() |> Jason.decode!()

insert_file = fn library, fixture, name ->
  if existing = Repo.get_by(MediaFileSchema, library_id: library.id, relative_path: name) do
    existing
  else
    path = Path.join(library.path, name)
    File.cp!(Path.join(directory, fixture), path)
    {:ok, stat} = File.stat(path, time: :posix)

    file =
      Repo.insert!(
        %MediaFileSchema{
          library_id: library.id,
          relative_path: name,
          size_bytes: stat.size,
          modified_at: DateTime.from_unix!(stat.mtime * 1_000_000, :microsecond),
          availability: :available,
          revision: 1,
          last_seen_generation: Ecto.UUID.generate()
        },
        log: false
      )

    {json, 0} =
      System.cmd("ffprobe", [
        "-v",
        "quiet",
        "-show_data",
        "-show_format",
        "-show_streams",
        "-of",
        "json",
        path
      ])

    {:ok, media} = FfprobeJson.parse(json)

    tracks =
      Enum.map(media.tracks, fn track ->
        Map.new(Map.from_struct(track), fn {key, value} ->
          {Atom.to_string(key), if(key == :kind, do: Atom.to_string(value), else: value)}
        end)
      end)

    Repo.insert!(
      %InspectionSchema{
        media_file_id: file.id,
        token: Ecto.UUID.generate(),
        observed_revision: 1,
        state: :succeeded,
        format: media.format,
        duration_ms: media.duration_ms,
        tracks: %{"items" => tracks}
      },
      log: false
    )

    file
  end
end

library = Repo.get!(LibrarySchema, ids["movie_library"])

fixtures =
  for name <- ["direct.mp4", "remux.mkv", "audio.mkv", "video.mp4", "both.mp4", "silent.mkv"],
      into: %{} do
    file = insert_file.(library, name, "negotiation-#{name}")

    Repo.get_by(MovieIdentificationSchema, media_file_id: file.id) ||
      Repo.insert!(
        %MovieIdentificationSchema{
          media_file_id: file.id,
          movie_id: ids["movie"],
          state: :automatic,
          origin: :automatic,
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          candidate_data: %{items: []},
          finished_at: DateTime.utc_now()
        },
        log: false
      )

    {name, file.id}
  end

series_library = Repo.get!(LibrarySchema, ids["series_library"])

next =
  Repo.get_by(EpisodeSchema, season_id: ids["season"], number: 2) ||
    Repo.insert!(
      EpisodeSchema.changeset(%EpisodeSchema{}, %{
        season_id: ids["season"],
        provider_id: 9_900_010,
        number: 2,
        title: "Synthetic continuation"
      }),
      log: false
    )

for {episode, part, name} <- [
      {ids["episode"], 1, "negotiation-part1.mp4"},
      {ids["episode"], 2, "negotiation-part2.mp4"},
      {next.id, nil, "negotiation-next.mp4"}
    ] do
  file = insert_file.(series_library, "direct.mp4", name)

  decision =
    Repo.get_by(SeriesIdentificationSchema, media_file_id: file.id) ||
      Repo.insert!(
        %SeriesIdentificationSchema{
          media_file_id: file.id,
          part_number: part,
          state: :automatic,
          origin: :automatic,
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          candidate_data: %{items: []},
          finished_at: DateTime.utc_now()
        },
        log: false
      )

  Repo.get_by(SeriesIdentificationEpisodeSchema,
    identification_id: decision.id,
    episode_id: episode
  ) ||
    Repo.insert!(
      %SeriesIdentificationEpisodeSchema{
        identification_id: decision.id,
        episode_id: episode,
        position: 1
      },
      log: false
    )
end

File.write!(
  Path.join(directory, "browser-ids.json"),
  Jason.encode!(%{
    movie: ids["movie"],
    episode: ids["episode"],
    next_episode: next.id,
    fixtures: fixtures
  })
)

IO.puts("Synthetic negotiation fixtures seeded; browser IDs written.")

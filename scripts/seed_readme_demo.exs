alias Bolognesa.Identity
alias Bolognesa.Infrastructure.LocalSourcePath

alias Bolognesa.Infrastructure.Persistence.{
  CatalogEntrySchema,
  EpisodeSchema,
  IdentificationEntrySchema,
  IdentificationSchema,
  InspectionSchema,
  LibrarySchema,
  MediaFileSchema,
  MovieSchema,
  SeasonSchema,
  SeriesSchema
}

alias Bolognesa.Music
alias Bolognesa.Repo

defmodule ReadmeScreenshotSeed do
  alias Bolognesa.Infrastructure.Persistence.{
    IdentificationEntrySchema,
    IdentificationSchema,
    MediaFileSchema
  }

  alias Bolognesa.Repo

  def insert_media_file!(library_id, directory, relative_path) do
    physical_path = Path.join(directory, relative_path)
    File.mkdir_p!(Path.dirname(physical_path))

    unless File.exists?(physical_path),
      do: File.write!(physical_path, "synthetic media placeholder")

    fixed_mtime = ~U[2025-01-15 12:00:00.000000Z]
    File.touch!(physical_path, DateTime.to_unix(fixed_mtime))

    Repo.insert!(%MediaFileSchema{
      library_id: library_id,
      relative_path: relative_path,
      size_bytes: File.stat!(physical_path).size,
      modified_at: fixed_mtime,
      availability: :available,
      revision: 1,
      last_seen_generation: Ecto.UUID.generate()
    })
  end

  @spec write_sample_audio!(String.t()) :: :ok
  def write_sample_audio!(path) do
    File.mkdir_p!(Path.dirname(path))
    sample_rate = 16_000

    pcm =
      for frame <- 0..(sample_rate * 10 - 1), into: <<>> do
        sample = round(:math.sin(2 * :math.pi() * 220 * frame / sample_rate) * 1600)
        <<sample::little-signed-16>>
      end

    File.write!(
      path,
      <<"RIFF", 36 + byte_size(pcm)::little-32, "WAVEfmt ", 16::little-32, 1::little-16,
        1::little-16, sample_rate::little-32, sample_rate * 2::little-32, 2::little-16,
        16::little-16, "data", byte_size(pcm)::little-32, pcm::binary>>
    )
  end

  def insert_identification!(media_file_id, state, catalog_entry_id \\ nil) do
    identification =
      Repo.insert!(%IdentificationSchema{
        media_file_id: media_file_id,
        state: state,
        origin: if(state == :automatic, do: :automatic),
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        needs_review: false,
        candidate_data: %{items: []},
        finished_at: if(state == :automatic, do: DateTime.utc_now())
      })

    if catalog_entry_id do
      Repo.insert!(%IdentificationEntrySchema{
        identification_id: identification.id,
        catalog_entry_id: catalog_entry_id,
        position: 1
      })
    end

    identification
  end
end

root = System.fetch_env!("BOLOGNESA_LIBRARY_ROOTS") |> String.split(":") |> hd()
movie_directory = Path.join(root, "movies")
series_directory = Path.join(root, "series")
music_directory = Path.join(root, "music")
File.mkdir_p!(movie_directory)
File.mkdir_p!(series_directory)
File.mkdir_p!(music_directory)
{:ok, movie_directory} = LocalSourcePath.canonical_directory(movie_directory)
{:ok, series_directory} = LocalSourcePath.canonical_directory(series_directory)
{:ok, music_directory} = LocalSourcePath.canonical_directory(music_directory)

movie_path = System.fetch_env!("BOLOGNESA_SCREENSHOT_VIDEO")
movie_name = "After the Signal.webm"
File.cp!(movie_path, Path.join(movie_directory, movie_name))

{:ok, _actor} =
  Identity.install_admin(%{
    name: "Demo Administrator",
    email: "demo@example.test",
    password: "demo-password-only-for-screenshots"
  })

movie_library =
  Repo.insert!(%LibrarySchema{
    name: "Movies",
    path: movie_directory,
    content_type: :movie
  })

series_library =
  Repo.insert!(%LibrarySchema{
    name: "Series",
    path: series_directory,
    content_type: :series
  })

movie_entry =
  Repo.insert!(%CatalogEntrySchema{
    kind: :movie,
    provider: :tmdb,
    resource_type: :movie,
    provider_id: 900_001
  })

movie =
  Repo.insert!(%MovieSchema{
    id: movie_entry.id,
    title: "After the Signal",
    original_title: "After the Signal",
    year: 2025,
    overview:
      "When a distant transmission reaches a quiet coastal town, a radio engineer follows its signal and discovers a message meant for someone else.",
    poster_path: "/readme-demo-poster.jpg",
    backdrop_path: "/readme-demo-backdrop.jpg"
  })

movie_file =
  ReadmeScreenshotSeed.insert_media_file!(movie_library.id, movie_directory, movie_name)

ReadmeScreenshotSeed.insert_identification!(movie_file.id, :automatic, movie.id)

review_file =
  ReadmeScreenshotSeed.insert_media_file!(
    movie_library.id,
    movie_directory,
    "Unidentified film.mkv"
  )

ReadmeScreenshotSeed.insert_identification!(review_file.id, :pending)

series_entry =
  Repo.insert!(%CatalogEntrySchema{
    kind: :series,
    provider: :tmdb,
    resource_type: :series,
    provider_id: 900_002
  })

series =
  Repo.insert!(%SeriesSchema{
    id: series_entry.id,
    title: "Small Hours",
    year: 2024,
    overview: "Six neighbours share a late-night radio show and the stories that reach it.",
    poster_path: "/readme-demo-poster.jpg",
    backdrop_path: "/readme-demo-backdrop.jpg"
  })

season_entry =
  Repo.insert!(%CatalogEntrySchema{
    kind: :season,
    provider: :tmdb,
    resource_type: :season,
    provider_id: 900_003
  })

season =
  Repo.insert!(%SeasonSchema{
    id: season_entry.id,
    series_id: series.id,
    number: 1,
    title: "Season 1",
    poster_path: "/readme-demo-poster.jpg"
  })

episode_entry =
  Repo.insert!(%CatalogEntrySchema{
    kind: :episode,
    provider: :tmdb,
    resource_type: :episode,
    provider_id: 900_004
  })

episode =
  Repo.insert!(%EpisodeSchema{
    id: episode_entry.id,
    season_id: season.id,
    number: 1,
    title: "The First Call",
    overview: "A caller asks the hosts to play a song no one has heard in years.",
    air_date: ~D[2024-09-12],
    still_path: "/readme-demo-backdrop.jpg"
  })

episode_path = "Small Hours/Season 1/Small Hours S01E01.webm"
File.mkdir_p!(Path.join(series_directory, "Small Hours/Season 1"))
File.cp!(movie_path, Path.join(series_directory, episode_path))

series_file =
  ReadmeScreenshotSeed.insert_media_file!(series_library.id, series_directory, episode_path)

ReadmeScreenshotSeed.insert_identification!(series_file.id, :automatic, episode.id)

series_review_file =
  ReadmeScreenshotSeed.insert_media_file!(
    series_library.id,
    series_directory,
    "Unidentified episode.mkv"
  )

ReadmeScreenshotSeed.insert_identification!(series_review_file.id, :pending)

music_library =
  Repo.insert!(%LibrarySchema{name: "Music", path: music_directory, content_type: :music})

music_tracks =
  for {name, tags} <- [
        {"Sample Ensemble/Night Signals/Northern Lights.wav",
         %{
           "title" => "Northern Lights",
           "artist" => "Sample Ensemble",
           "album" => "Night Signals",
           "track" => "1"
         }},
        {"Sample Ensemble/Night Signals/After Rain.wav",
         %{
           "title" => "After Rain",
           "artist" => "Sample Ensemble",
           "album" => "Night Signals",
           "track" => "2"
         }},
        {"Evening Sketch.wav", %{}}
      ] do
    ReadmeScreenshotSeed.write_sample_audio!(Path.join(music_directory, name))
    file = ReadmeScreenshotSeed.insert_media_file!(music_library.id, music_directory, name)
    tags = Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags.from_raw(tags)

    Repo.insert!(
      %InspectionSchema{
        media_file_id: file.id,
        token: Ecto.UUID.generate(),
        observed_revision: 1,
        state: :succeeded,
        format: "wav",
        duration_ms: 10_000,
        tracks: %{"items" => [%{"kind" => "audio", "codec" => "pcm_s16le"}]},
        music_tags: Map.from_struct(tags)
      },
      log: false
    )

    :ok = Music.refresh_track(file.id, 1)
    Repo.get_by!(Bolognesa.Infrastructure.Persistence.MusicTrackSchema, media_file_id: file.id)
  end

System.fetch_env!("BOLOGNESA_SCREENSHOT_IDS")
|> File.write!(
  Jason.encode!(%{
    movie_library: movie_library.id,
    series_library: series_library.id,
    music_library: music_library.id,
    music_track: hd(music_tracks).id,
    music_artist: hd(music_tracks).artist_id,
    music_album: hd(music_tracks).album_id,
    music_second_track: Enum.at(music_tracks, 1).id,
    movie: movie.id,
    series: series.id,
    season: season.id,
    episode: episode.id
  })
)

IO.puts("Seeded deterministic README screenshot data.")

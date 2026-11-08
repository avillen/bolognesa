alias Bolognesa.Infrastructure.Persistence.{
  InspectionSchema,
  LibrarySchema,
  MediaFileSchema,
  MusicTrackSchema,
  UserSchema
}

alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags
alias Bolognesa.{Music, Repo}

unless Mix.env() == :dev and
         String.starts_with?(System.fetch_env!("BOLOGNESA_DB_NAME"), "bolognesa_demo_") do
  raise "Demo music requires a dedicated development demo database"
end

root = System.fetch_env!("BOLOGNESA_LIBRARY_ROOTS")
ids = root |> Path.join("sample-ids.json") |> File.read!() |> Jason.decode!()
library = Repo.get!(LibrarySchema, ids["music_library"])
admin = Repo.get_by!(UserSchema, role: "admin")

albums = [
  {"Harbor Lights", "Blue Hour", ["First Light", "Open Water", "Homeward"], 1},
  {"Harbor Lights", "Coastal Roads", ["Mile Zero", "Headlands", "Last Ferry"], 3},
  {"The Paper Planets", "Little Orbits", ["Satellite", "Circles", "Morning Sky"], 2},
  {"The Paper Planets", "Field Notes", ["Wildflowers", "Low Clouds", "Silver Path"], nil},
  {"Glass Garden", "Still Life", ["Glasshouse", "Small Wonders", "Evening Air"], nil}
]

for {{artist, album, titles, heard_track}, album_index} <- Enum.with_index(albums) do
  for {title, index} <- Enum.with_index(titles, 1) do
    relative = Path.join(["Demo Collection", artist, album, "#{index} - #{title}.wav"])

    unless Repo.get_by(MediaFileSchema, library_id: library.id, relative_path: relative) do
      path = Path.join(library.path, relative)
      File.mkdir_p!(Path.dirname(path))

      if File.exists?(path),
        do: raise("Demo music path already exists; leaving it unchanged: #{path}")

      sample_rate = 16_000

      pcm =
        for frame <- 0..(sample_rate * 10 - 1), into: <<>> do
          sample =
            round(
              :math.sin(2 * :math.pi() * (220 + album_index * 40) * frame / sample_rate) * 1600
            )

          <<sample::little-signed-16>>
        end

      File.write!(
        path,
        <<"RIFF", 36 + byte_size(pcm)::little-32, "WAVEfmt ", 16::little-32, 1::little-16,
          1::little-16, sample_rate::little-32, sample_rate * 2::little-32, 2::little-16,
          16::little-16, "data", byte_size(pcm)::little-32, pcm::binary>>
      )

      mtime = ~U[2025-01-15 12:00:00.000000Z]
      File.touch!(path, DateTime.to_unix(mtime))

      file =
        Repo.insert!(%MediaFileSchema{
          library_id: library.id,
          relative_path: relative,
          size_bytes: File.stat!(path).size,
          modified_at: mtime,
          availability: :available,
          revision: 1,
          last_seen_generation: Ecto.UUID.generate()
        })

      tags =
        MusicTags.from_raw(%{
          "title" => title,
          "artist" => artist,
          "album" => album,
          "track" => Integer.to_string(index)
        })

      Repo.insert!(%InspectionSchema{
        media_file_id: file.id,
        token: Ecto.UUID.generate(),
        observed_revision: 1,
        state: :succeeded,
        format: "wav",
        duration_ms: 10_000,
        tracks: %{"items" => [%{"kind" => "audio", "codec" => "pcm_s16le"}]},
        music_tags: Map.from_struct(tags)
      })

      :ok = Music.refresh_track(file.id, 1)

      if index == heard_track do
        track = Repo.get_by!(MusicTrackSchema, media_file_id: file.id)
        date = DateTime.add(DateTime.utc_now(), -album_index * 86_400, :second)

        Repo.query!(
          "INSERT INTO music_listening_activity (user_id, track_id, last_played_at) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
          [admin.id, track.id, date], log: false)
      end
    end
  end
end

IO.puts("Demo music is ready; existing tracks and activity were left unchanged.")

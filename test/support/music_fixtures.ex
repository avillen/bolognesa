defmodule Bolognesa.MusicFixtures do
  @moduledoc false
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, LibrarySchema, MediaFileSchema}
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags
  alias Bolognesa.Repo
  @spec music_fixture(keyword()) :: map()
  def music_fixture(opts \\ []) do
    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{
          name: "Sample music",
          path: "/sample-music-#{System.unique_integer([:positive])}",
          content_type: :music
        }),
        log: false
      )

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: Keyword.get(opts, :relative_path, "album/sample.mp3"),
          size_bytes: 10,
          modified_at: ~U[2026-10-03 00:00:00.000000Z],
          availability: Keyword.get(opts, :availability, :available),
          revision: Keyword.get(opts, :revision, 1),
          last_seen_generation: Ecto.UUID.generate()
        }),
        log: false
      )

    tags = MusicTags.from_raw(Keyword.get(opts, :tags, %{}))

    inspection =
      Repo.insert!(
        InspectionSchema.changeset(%InspectionSchema{}, %{
          media_file_id: file.id,
          token: Ecto.UUID.generate(),
          observed_revision: file.revision,
          state: Keyword.get(opts, :inspection_state, :succeeded),
          format: "mp3",
          duration_ms: 2500,
          tracks: %{"items" => [%{"kind" => "audio", "codec" => "mp3"}]},
          music_tags: Map.from_struct(tags)
        }),
        log: false
      )

    %{actor: %Actor{id: 1, role: :admin}, library: library, file: file, inspection: inspection}
  end

  @spec refresh_fixture(keyword()) :: map()
  def refresh_fixture(opts \\ []) do
    fixture = music_fixture(opts)
    :ok = Bolognesa.Music.refresh_track(fixture.file.id, fixture.file.revision)

    Map.put(
      fixture,
      :track,
      Repo.get_by!(Bolognesa.Infrastructure.Persistence.MusicTrackSchema,
        media_file_id: fixture.file.id
      )
    )
  end
end

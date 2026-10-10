defmodule Bolognesa.Playback.StartPlaybackTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Playback
  alias Bolognesa.Playback.Domain.Source
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Persistence.MovieSchema

  alias Bolognesa.Persistence.IdentificationSchema

  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Persistence.InspectionSchema

  test "authorizes only a currently linked available version" do
    actor = %Actor{id: 1, role: :admin}
    movie = movie(100)
    other = movie(101)

    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{name: "Playback", path: "/playback"})
      )

    file = file(library.id, "film.mp4", :available)
    missing = file(library.id, "missing.mp4", :missing)
    identification = identify(file.id, movie.id)
    identify(missing.id, movie.id)

    assert {:ok, %{path: "/playback", relative_path: "film.mp4", size_bytes: 8} = source} =
             Playback.start(actor, movie.id, file.id)

    assert source.__struct__ == Source

    assert {:error, :forbidden} = Playback.start(nil, movie.id, file.id)
    assert {:error, :not_found} = Playback.start(actor, other.id, file.id)
    assert {:error, :missing} = Playback.start(actor, movie.id, missing.id)
    assert {:error, :not_found} = Playback.start(actor, movie.id, 0)

    identification
    |> IdentificationSchema.changeset(%{movie_id: other.id, state: :manual, origin: :manual})
    |> Repo.update!()

    assert {:error, :not_found} = Playback.start(actor, movie.id, file.id)
    assert {:ok, %{relative_path: "film.mp4"}} = Playback.start(actor, other.id, file.id)
  end

  test "uses only a successful inspection for the current file revision" do
    actor = %Actor{id: 1, role: :admin}
    movie = movie(102)

    library =
      Repo.insert!(
        LibrarySchema.changeset(
          %LibrarySchema{},
          %{name: "Inspected playback", path: "/playback"}
        )
      )

    file = file(library.id, "film.avi", :available)
    identify(file.id, movie.id)

    inspection =
      Repo.insert!(
        InspectionSchema.changeset(%InspectionSchema{}, %{
          media_file_id: file.id,
          token: Ecto.UUID.generate(),
          observed_revision: file.revision,
          state: :succeeded,
          format: "avi",
          duration_ms: 60_000,
          tracks: %{
            "items" => [
              %{"kind" => "video", "codec" => "mpeg4"},
              %{"kind" => "audio", "codec" => "ac3"}
            ]
          }
        })
      )

    assert {:ok, :video, %{duration_ms: 60_000}} = Playback.delivery(actor, movie.id, file.id)

    inspection
    |> InspectionSchema.changeset(%{state: :failed})
    |> Repo.update!()

    assert {:ok, :direct, %{duration_ms: nil, tracks: []}} =
             Playback.delivery(actor, movie.id, file.id)
  end

  defp movie(provider_id) do
    Repo.insert!(
      MovieSchema.changeset(%MovieSchema{}, %{
        provider: :tmdb,
        provider_id: provider_id,
        title: "Movie"
      })
    )
  end

  defp file(library_id, relative_path, availability) do
    Repo.insert!(
      MediaFileSchema.changeset(%MediaFileSchema{}, %{
        library_id: library_id,
        relative_path: relative_path,
        size_bytes: 8,
        modified_at: DateTime.utc_now(),
        availability: availability,
        last_seen_generation: Ecto.UUID.generate()
      })
    )
  end

  defp identify(file_id, movie_id) do
    Repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: file_id,
        movie_id: movie_id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic
      })
    )
  end
end

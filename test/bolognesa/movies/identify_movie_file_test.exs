defmodule Bolognesa.Movies.IdentifyMediaFileTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Movies.Application.UseCases.IdentifyMovieFile
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Domain.ReadModels.FileToIdentify
  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate
  alias Bolognesa.Movies.Domain.ValueObjects.MovieDetails
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository

  defmodule Provider do
    def search("Mi pelicula", 2001),
      do: {:ok, [%MovieCandidate{provider_id: 42, title: "Otra pelicula", year: 2002}]}

    def details(42), do: {:ok, %MovieDetails{provider_id: 42, title: "Otra pelicula", year: 2002}}
  end

  defmodule ExactProvider do
    def search("Film", nil),
      do: {:ok, [%MovieCandidate{provider_id: 43, title: "Film", year: nil}]}

    def details(43), do: {:ok, %MovieDetails{provider_id: 43, title: "Film", year: nil}}
  end

  defmodule NeverCalledProvider do
    def search(_, _), do: raise("release-only title reached provider")
  end

  setup do
    owner = self()
    handler = {__MODULE__, make_ref()}

    events =
      for outcome <- [:completed, :stale, :retryable],
          do: [:bolognesa, :movies, :identification, outcome]

    :telemetry.attach_many(
      handler,
      events,
      fn event, measurements, metadata, _ -> send(owner, {event, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  test "selects first result and marks a mismatch for review" do
    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Movies", path: "/movies"}))

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "Mi.pelicula.(2001).mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    token = Ecto.UUID.generate()

    Repo.insert!(
      MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: token,
        state: :pending
      })
    )

    assert {:ok, %{relative_path: "Mi.pelicula.(2001).mkv"} = beginning_file} =
             Repository.begin_identification(file.id, token, nil)

    assert beginning_file.__struct__ == FileToIdentify

    assert :ok = IdentifyMovieFile.call(file.id, token, 1, Repository, Provider)
    assert_receive {[:bolognesa, :movies, :identification, :completed], _, %{result: :review}}

    assert {:ok,
            %{state: :automatic, needs_review?: true, movie_id: movie_id} =
              identification} =
             Repository.get(file.id)

    assert identification.__struct__ == Identification

    assert is_integer(movie_id)
    assert :ok = IdentifyMovieFile.call(file.id, token, 2, Repository, Provider)
  end

  test "reanalysis removes automatic associations and ignores the old token" do
    {file, token} = pending_file("Film.mkv")
    assert :ok = IdentifyMovieFile.call(file.id, token, 1, Repository, ExactProvider)
    assert {:ok, %{movie_id: _}} = Repository.get(file.id)
    assert {:ok, pending} = Repository.retry(file.id)
    assert pending.state == :pending
    assert pending.movie_id == nil

    assert {:ok, :stale} =
             Repository.complete(
               file.id,
               token,
               [],
               %MovieDetails{provider_id: 43, title: "Film"},
               false
             )

    assert {:ok, %{movie_id: nil}} = Repository.get(file.id)
  end

  test "matching title without years completes without review" do
    {file, token} = pending_file("Film.mkv")
    assert :ok = IdentifyMovieFile.call(file.id, token, 1, Repository, ExactProvider)
    assert_receive {[:bolognesa, :movies, :identification, :completed], _, %{result: :matched}}

    assert {:ok, %Identification{state: :automatic, needs_review?: false}} =
             Repository.get(file.id)
  end

  test "release-only filename never reaches provider" do
    {file, token} = pending_file("1080p.WEB-DL.x265.mkv")
    assert :ok = IdentifyMovieFile.call(file.id, token, 1, Repository, NeverCalledProvider)
    assert {:ok, %{state: :failed, failure_reason: "unusable_name"}} = Repository.get(file.id)
  end

  defp pending_file(name) do
    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{name: name, path: "/#{Ecto.UUID.generate()}"})
      )

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: name,
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    token = Ecto.UUID.generate()

    Repo.insert!(
      MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: token,
        state: :pending
      })
    )

    {file, token}
  end
end

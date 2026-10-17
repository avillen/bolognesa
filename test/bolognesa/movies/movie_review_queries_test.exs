defmodule Bolognesa.Movies.MovieReviewQueriesTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Item, as: MovieReviewItem
  alias Bolognesa.Movies.Application.UseCases.ListMovieReviewItems.Response, as: MovieReviewPage
  alias Bolognesa.Movies.Domain.Entities.Identification, as: IdentificationDecision
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovie
  alias Bolognesa.Movies.Domain.ReadModels.ReviewMovieFile
  alias Bolognesa.Movies.Infrastructure.Readers.EctoMovieReviewReader

  test "shows pending, failed and manually unidentified files to administrators only" do
    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Review", path: "/review"}))

    for {name, state} <- [
          {"a.mkv", :pending},
          {"b.mkv", :failed},
          {"c.mkv", :manual_unidentified}
        ] do
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

      Repo.insert!(
        MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
          media_file_id: file.id,
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          state: state,
          origin: if(state == :manual_unidentified, do: :manual, else: nil)
        })
      )
    end

    movie =
      Repo.insert!(
        movie_changeset(%{
          provider: :tmdb,
          provider_id: 42,
          title: "Película dudosa"
        })
      )

    linked_file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "d.mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    Bolognesa.MovieIdentificationFixtures.insert_decision!(
      %{
        media_file_id: linked_file.id,
        observed_revision: 1,
        token: Ecto.UUID.generate(),
        state: :automatic,
        origin: :automatic,
        needs_review: true
      },
      movie.id
    )

    assert {:error, :forbidden} = Movies.list_review_items(nil, 1)

    assert {:ok, %MovieReviewPage{items: [%MovieReviewItem{} | _] = items, total: 4}} =
             Movies.list_review_items(%AuthenticatedUser{id: 1, role: :admin}, 1)

    assert Enum.map(items, & &1.filename) == ["a.mkv", "b.mkv", "c.mkv", "d.mkv"]
    assert List.last(items).movie_title == "Película dudosa"

    assert {:ok, {[{%IdentificationDecision{}, file, nil} | _] = entries, 4}} =
             EctoMovieReviewReader.list_review_items(1)

    assert file.__struct__ == ReviewMovieFile
    assert file.relative_path == "a.mkv"

    assert {_, _, %ReviewMovie{id: movie_id, title: "Película dudosa"}} =
             List.last(entries)

    assert movie_id == movie.id
  end

  defp movie_changeset(attrs),
    do: MovieSchema.changeset(%MovieSchema{}, Map.put_new(attrs, :provider, :tmdb))
end

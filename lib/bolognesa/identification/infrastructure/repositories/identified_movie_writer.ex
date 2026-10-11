defmodule Bolognesa.Identification.Infrastructure.Repositories.IdentifiedMovieWriter do
  @moduledoc false
  alias Bolognesa.Identification.Domain.ValueObjects.Movies.MovieDetails
  alias Bolognesa.Identification.Domain.ValueObjects.Movies.NewMovie
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Repo

  @spec upsert!(MovieDetails.t()) :: pos_integer()
  def upsert!(%MovieDetails{} = details) do
    attrs = details |> Map.from_struct() |> Map.put(:provider, :tmdb)

    case NewMovie.new(attrs) do
      {:ok, movie} -> persist!(movie)
      {:error, :invalid_movie} -> raise ArgumentError, "invalid movie"
    end
  end

  defp persist!(movie) do
    identity = %{
      kind: :movie,
      provider: :tmdb,
      resource_type: :movie,
      provider_id: movie.provider_id
    }

    %CatalogEntrySchema{}
    |> CatalogEntrySchema.changeset(identity)
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:provider, :resource_type, :provider_id],
      log: false
    )

    entry =
      Repo.get_by!(
        CatalogEntrySchema,
        Map.take(identity, [:provider, :resource_type, :provider_id]),
        log: false
      )

    %MovieSchema{id: entry.id}
    |> MovieSchema.changeset(Map.from_struct(movie) |> Map.drop([:provider, :provider_id]))
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:id], log: false)

    true = entry.kind == :movie
    Repo.get!(MovieSchema, entry.id, log: false)
    entry.id
  end
end

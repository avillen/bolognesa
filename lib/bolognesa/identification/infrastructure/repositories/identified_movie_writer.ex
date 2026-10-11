defmodule Bolognesa.Identification.Infrastructure.Repositories.IdentifiedMovieWriter do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Identification.Domain.ValueObjects.Movies.MovieDetails
  alias Bolognesa.Identification.Domain.ValueObjects.Movies.NewMovie
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  alias Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema
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

  @spec delete_orphaned!([pos_integer()]) :: :ok
  def delete_orphaned!(ids) do
    ids
    |> Enum.sort()
    |> Enum.each(&delete_orphaned_movie!/1)

    :ok
  end

  defp delete_orphaned_movie!(id) do
    entry =
      Repo.one(
        from(entry in CatalogEntrySchema,
          where: entry.id == ^id and entry.kind == :movie,
          lock: "FOR UPDATE"
        ),
        log: false
      )

    referenced? =
      Repo.exists?(from(row in IdentificationEntrySchema, where: row.catalog_entry_id == ^id),
        log: false
      )

    if entry && !referenced? do
      Repo.delete_all(from(movie in MovieSchema, where: movie.id == ^id), log: false)
      Repo.delete!(entry, log: false)
    end
  end

  defp persist!(movie) do
    identity = %{
      kind: :movie,
      provider: :tmdb,
      resource_type: :movie,
      provider_id: movie.provider_id
    }

    entry =
      %CatalogEntrySchema{}
      |> CatalogEntrySchema.changeset(identity)
      |> Repo.insert!(
        on_conflict: [set: [provider_id: movie.provider_id]],
        conflict_target: [:provider, :resource_type, :provider_id],
        returning: true,
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

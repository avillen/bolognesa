defmodule Bolognesa.Movies.Infrastructure.Repositories.IdentifiedMovieWriter do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies.Domain.ValueObjects.MovieDetails
  alias Bolognesa.Movies.Domain.ValueObjects.NewMovie
  alias Bolognesa.Repo

  @spec upsert!(MovieDetails.t()) :: pos_integer()
  def upsert!(%MovieDetails{} = details) do
    attrs = details |> Map.from_struct() |> Map.put(:provider, :tmdb)
    {:ok, movie} = NewMovie.new(attrs)

    row =
      Repo.insert!(MovieSchema.changeset(%MovieSchema{}, Map.from_struct(movie)),
        on_conflict: [set: [provider_id: movie.provider_id]],
        conflict_target: [:provider, :provider_id],
        returning: true,
        log: false
      )

    row.id
  end

  @spec delete_orphaned!([pos_integer()]) :: :ok
  def delete_orphaned!(ids) do
    Enum.each(Enum.sort(ids), fn id ->
      Repo.one(from(row in MovieSchema, where: row.id == ^id, lock: "FOR UPDATE"), log: false)

      referenced =
        from(row in MovieIdentificationSchema,
          where: not is_nil(row.movie_id),
          select: row.movie_id
        )

      Repo.delete_all(
        from(row in MovieSchema, where: row.id == ^id and row.id not in subquery(referenced)),
        log: false
      )
    end)

    :ok
  end
end

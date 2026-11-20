defmodule Bolognesa.Movies.Infrastructure.Repositories.IdentifiedMovieWriter do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies.Domain.ValueObjects.ProviderMovie
  alias Bolognesa.Repo

  @spec upsert!(ProviderMovie.t()) :: pos_integer()
  def upsert!(%ProviderMovie{} = details) do
    attrs = details |> Map.from_struct() |> Map.put(:provider, :tmdb)

    row =
      Repo.insert!(MovieSchema.changeset(%MovieSchema{}, attrs),
        on_conflict: [set: [provider_id: details.provider_id]],
        conflict_target: [:provider, :provider_id],
        returning: true,
        log: false
      )

    row.id
  end

  @spec delete_orphaned!([pos_integer()]) :: :ok
  def delete_orphaned!(ids) do
    Enum.each(Enum.sort(ids), fn id ->
      Repo.get(lock(MovieSchema, "FOR UPDATE"), id, log: false)

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

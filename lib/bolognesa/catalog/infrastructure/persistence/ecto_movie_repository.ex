defmodule Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository do
  @moduledoc false
  @behaviour Bolognesa.Catalog.Application.Ports.MovieRepository

  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema
  alias Bolognesa.Repo

  @spec upsert!(module(), Bolognesa.Identification.Domain.MovieDetails.t()) :: MovieSchema.t()
  def upsert!(repo, details) do
    attrs = details |> Map.from_struct() |> Map.put(:provider, :tmdb)

    %MovieSchema{}
    |> MovieSchema.changeset(attrs)
    |> repo.insert!(on_conflict: :nothing, conflict_target: [:provider, :provider_id], log: false)

    repo.get_by!(MovieSchema, provider: :tmdb, provider_id: details.provider_id)
  end

  @spec get(pos_integer()) :: {:ok, MovieSchema.t()} | {:error, :not_found | :unavailable}
  def get(id) do
    case Repo.get(MovieSchema, id) do
      nil -> {:error, :not_found}
      movie -> {:ok, movie}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end

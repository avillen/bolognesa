defmodule Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository do
  @moduledoc false
  @behaviour Bolognesa.Catalog.Application.Ports.MovieRepository

  alias Bolognesa.Catalog.Domain.NewMovie
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieMapper
  alias Bolognesa.Persistence.MovieSchema

  @impl true
  def upsert!(repo, %NewMovie{} = new_movie) do
    attrs = Map.from_struct(new_movie)

    %MovieSchema{}
    |> MovieSchema.changeset(attrs)
    |> repo.insert!(on_conflict: :nothing, conflict_target: [:provider, :provider_id], log: false)

    repo.get_by!(MovieSchema, provider: :tmdb, provider_id: new_movie.provider_id)
    |> MovieMapper.to_movie()
  end
end

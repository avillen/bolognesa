defmodule Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieMapper do
  @moduledoc false
  alias Bolognesa.Catalog.Domain.Movie
  alias Bolognesa.Persistence.MovieSchema

  @spec to_movie(MovieSchema.t()) :: Movie.t()
  def to_movie(schema) do
    %Movie{
      id: schema.id,
      provider: schema.provider,
      provider_id: schema.provider_id,
      title: schema.title,
      original_title: schema.original_title,
      year: schema.year,
      overview: schema.overview,
      poster_path: schema.poster_path,
      backdrop_path: schema.backdrop_path
    }
  end
end

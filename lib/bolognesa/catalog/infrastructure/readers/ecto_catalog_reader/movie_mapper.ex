defmodule Bolognesa.Catalog.Infrastructure.Readers.EctoCatalogReader.MovieMapper do
  @moduledoc false
  alias Bolognesa.Catalog.Domain.Movie
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema

  @spec to_movie(MovieSchema.t(), CatalogEntrySchema.t()) :: Movie.t()
  def to_movie(schema, entry) do
    %Movie{
      id: schema.id,
      provider: entry.provider,
      provider_id: entry.provider_id,
      title: schema.title,
      original_title: schema.original_title,
      year: schema.year,
      overview: schema.overview,
      poster_path: schema.poster_path,
      backdrop_path: schema.backdrop_path
    }
  end
end

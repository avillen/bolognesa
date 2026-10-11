defmodule Bolognesa.Catalog do
  @moduledoc "Movie catalog queries."
  alias Bolognesa.Catalog.Application.Dto.MovieDetail
  alias Bolognesa.Catalog.Application.Dto.MoviePage
  alias Bolognesa.Catalog.Application.GetMovie
  alias Bolognesa.Catalog.Application.ListMovies
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoCatalogReader
  alias Bolognesa.Identity.Domain.Actor

  @spec list_movies(Actor.t(), binary(), pos_integer()) ::
          {:ok, MoviePage.t()} | {:error, :forbidden | :invalid_query | :unavailable}
  def list_movies(actor, query, page), do: ListMovies.call(actor, query, page, EctoCatalogReader)

  @spec get_movie(Actor.t(), pos_integer()) ::
          {:ok, MovieDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_movie(actor, id), do: GetMovie.call(actor, id, EctoCatalogReader)
end

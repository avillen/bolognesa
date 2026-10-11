defmodule Bolognesa.Catalog do
  @moduledoc "Movie catalog queries and the controlled shared-transaction writer."
  alias Bolognesa.Catalog.Application.Dto.MovieDetail
  alias Bolognesa.Catalog.Application.Dto.MoviePage
  alias Bolognesa.Catalog.Application.GetMovie
  alias Bolognesa.Catalog.Application.ListMovies
  alias Bolognesa.Catalog.Domain.Movie
  alias Bolognesa.Catalog.Domain.NewMovie
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoCatalogReader
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository
  alias Bolognesa.Identity.Domain.Actor

  @spec list_movies(Actor.t(), binary(), pos_integer()) ::
          {:ok, MoviePage.t()} | {:error, :forbidden | :invalid_query | :unavailable}
  def list_movies(actor, query, page), do: ListMovies.call(actor, query, page, EctoCatalogReader)

  @spec get_movie(Actor.t(), pos_integer()) ::
          {:ok, MovieDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_movie(actor, id), do: GetMovie.call(actor, id, EctoCatalogReader)

  @doc "Upsert a movie inside the caller's transaction and return its identifier."
  @spec upsert_in_transaction!(module(), NewMovie.attrs()) :: Movie.id()
  def upsert_in_transaction!(repo, attrs) do
    case NewMovie.new(attrs) do
      {:ok, new_movie} -> EctoMovieRepository.upsert!(repo, new_movie).id
      {:error, :invalid_movie} -> raise ArgumentError, "invalid movie"
    end
  end
end

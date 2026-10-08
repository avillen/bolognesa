defmodule Bolognesa.Catalog do
  @moduledoc "Movie catalog queries and the controlled shared-transaction writer."
  alias Bolognesa.Catalog.Application.{GetMovie, ListMovies}
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoCatalogReader
  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository
  alias Bolognesa.Identity.Domain.Actor

  @spec list_movies(Actor.t() | nil, binary(), pos_integer()) :: {:ok, map()} | {:error, atom()}
  def list_movies(actor, query, page), do: ListMovies.call(actor, query, page, EctoCatalogReader)

  @spec get_movie(Actor.t() | nil, pos_integer()) :: {:ok, map()} | {:error, atom()}
  def get_movie(actor, id), do: GetMovie.call(actor, id, EctoCatalogReader)

  @doc false
  @spec upsert_in_transaction!(module(), map()) ::
          %{id: pos_integer()}
  def upsert_in_transaction!(repo, details), do: EctoMovieRepository.upsert!(repo, details)
end

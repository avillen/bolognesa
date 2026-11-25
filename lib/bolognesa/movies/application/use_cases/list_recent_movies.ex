defmodule Bolognesa.Movies.Application.UseCases.ListRecentMovies do
  @moduledoc "Authorized, bounded lookup of the account's recently watched movies."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.ReadQuery

  @type result :: {:ok, [Movie.t()]} | {:error, :forbidden | :invalid_query | :unavailable}

  @spec call(AuthenticatedUser.t() | nil, pos_integer() | nil, WatchedMoviesReader.adapter()) ::
          result()
  def call(actor, library_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_optional_id(library_id) do
      reader.list_recent_movies(actor.id, library_id)
    end
  end
end

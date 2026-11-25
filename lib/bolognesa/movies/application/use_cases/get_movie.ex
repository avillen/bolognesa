defmodule Bolognesa.Movies.Application.UseCases.GetMovie do
  @moduledoc "Authorize a movie detail read with the account's watched date."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Movies.Application.Ports.Readers.MoviesReader
  alias Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader
  alias Bolognesa.Movies.Application.UseCases.GetMovie.Response, as: MovieDetail
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.ReadQuery

  @spec call(
          AuthenticatedUser.t(),
          Movie.id(),
          MoviesReader.adapter(),
          WatchedMoviesReader.adapter()
        ) ::
          {:ok, MovieDetail.t()}
          | {:error, :forbidden | :not_found | :unavailable | :too_many_versions}
  def call(actor, id, reader, watched_reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_id(id),
         {:ok, result} <- reader.get_movie(id),
         {:ok, last_watched_at} <- watched_reader.fetch_last_watched_at(actor.id, id) do
      {:ok, MovieDetail.from_domain(result, last_watched_at)}
    end
  end
end

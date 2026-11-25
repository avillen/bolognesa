defmodule Bolognesa.Movies.Application.UseCases.MarkWatchedMovie do
  @moduledoc "Mark a catalog movie as watched now for the authenticated account."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader
  alias Bolognesa.Movies.Application.Ports.Repositories.WatchedMoviesRepository
  alias Bolognesa.Movies.Domain.ReadModels.Movie

  @type result :: :ok | {:error, :forbidden | :not_found | :unavailable}
  @spec call(
          AuthenticatedUser.t() | nil,
          Movie.id(),
          WatchedMoviesReader.adapter(),
          WatchedMoviesRepository.adapter()
        ) :: result()
  def call(actor, movie_id, reader, repository) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- reader.fetch_movie(movie_id) do
      repository.upsert(actor.id, movie_id, DateTime.utc_now())
    end
  end
end

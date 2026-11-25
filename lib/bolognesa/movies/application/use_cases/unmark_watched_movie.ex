defmodule Bolognesa.Movies.Application.UseCases.UnmarkWatchedMovie do
  @moduledoc "Remove a movie from the authenticated account's watched movies."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Movies.Application.Ports.Repositories.WatchedMoviesRepository
  alias Bolognesa.Movies.Domain.ReadModels.Movie

  @spec call(AuthenticatedUser.t() | nil, Movie.id(), WatchedMoviesRepository.adapter()) ::
          :ok | {:error, :forbidden | :unavailable}
  def call(actor, movie_id, repository) do
    with :ok <- Accounts.authorize(actor, :admin), do: repository.delete(actor.id, movie_id)
  end
end

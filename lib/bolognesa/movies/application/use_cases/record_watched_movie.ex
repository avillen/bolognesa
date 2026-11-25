defmodule Bolognesa.Movies.Application.UseCases.RecordWatchedMovie do
  @moduledoc "Validate the reported file through Movies, then record the movie as watched."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Movies.Application.Ports.Readers.WatchedMoviesReader
  alias Bolognesa.Movies.Application.Ports.Repositories.WatchedMoviesRepository
  alias Bolognesa.Movies.Domain.ReadModels.Movie

  @type result :: :ok | {:error, :forbidden | :not_found | :unavailable}
  @spec call(
          AuthenticatedUser.t() | nil,
          Movie.id(),
          pos_integer(),
          WatchedMoviesReader.adapter(),
          WatchedMoviesRepository.adapter()
        ) :: result()
  def call(actor, movie_id, file_id, reader, repository) do
    result =
      with :ok <- Accounts.authorize(actor, :admin),
           :ok <- reader.fetch_played_movie(movie_id, file_id) do
        repository.upsert(actor.id, movie_id, DateTime.utc_now())
      end

    observe(result, actor, file_id)
  end

  defp observe(:ok, _actor, _file_id), do: :ok

  defp observe({:error, reason} = result, actor, file_id) do
    Events.emit(:movies, :watched_entries, :failed, %{
      user_id: if(actor, do: actor.id),
      file_id: file_id,
      reason: reason
    })

    result
  end
end

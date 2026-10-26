defmodule Bolognesa.Series.Application.UseCases.FetchNextPlayableEpisode do
  @moduledoc "Authorize continuation through physical parts before advancing to another episode."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Domain.ReadModels.EpisodeTarget

  @spec call(AuthenticatedUser.t(), pos_integer(), pos_integer(), SeriesReader.adapter()) ::
          {:ok, EpisodeTarget.t()}
          | :not_found
          | {:error, :forbidden | :unavailable | :part_unavailable}
  def call(actor, episode_id, file_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin) do
      reader.fetch_next_playable_episode(episode_id, file_id)
    end
  end
end

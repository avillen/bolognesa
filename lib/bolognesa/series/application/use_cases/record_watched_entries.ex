defmodule Bolognesa.Series.Application.UseCases.RecordWatchedEntries do
  @moduledoc "Reauthorize the reported file through Playback, then record its current season entries."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Playback
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
  alias Bolognesa.Series.Domain.ReadModels.Episode

  @type result ::
          :ok | {:error, :forbidden | :not_found | :missing | :unavailable | :too_many_entries}
  @spec call(
          AuthenticatedUser.t() | nil,
          Episode.id(),
          pos_integer(),
          WatchedEntriesReader.adapter(),
          WatchedEntriesRepository.adapter()
        ) :: result()
  def call(actor, episode_id, file_id, reader, repository) do
    with :ok <- Accounts.authorize(actor, :admin),
         {:ok, _source} <- Playback.start_video(actor, {:episode, episode_id}, file_id),
         {:ok, entries} <- reader.list_played_entries(episode_id, file_id) do
      repository.upsert(actor.id, entries, DateTime.utc_now())
    else
      :not_found -> {:error, :not_found}
      error -> error
    end
  end
end

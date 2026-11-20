defmodule Bolognesa.Series.Application.UseCases.RecordWatchedEntries do
  @moduledoc "Validate the reported file through Series, then record its current entries."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
  alias Bolognesa.Series.Domain.ReadModels.Episode

  @type result ::
          :ok | {:error, :forbidden | :not_found | :unavailable}
  @spec call(
          AuthenticatedUser.t() | nil,
          Episode.id(),
          pos_integer(),
          WatchedEntriesReader.adapter(),
          WatchedEntriesRepository.adapter()
        ) :: result()
  def call(actor, episode_id, file_id, reader, repository) do
    result =
      with :ok <- Accounts.authorize(actor, :admin),
           {:ok, entries} <- reader.fetch_played_entries(episode_id, file_id) do
        repository.upsert(actor.id, entries, DateTime.utc_now())
      end

    observe(result, actor, file_id)
  end

  defp observe(:ok, _actor, _file_id), do: :ok

  defp observe({:error, reason} = result, actor, file_id) do
    Events.emit(:series, :watched_entries, :failed, %{
      user_id: if(actor, do: actor.id),
      file_id: file_id,
      reason: reason
    })

    result
  end
end

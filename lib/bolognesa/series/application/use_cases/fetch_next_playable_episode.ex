defmodule Bolognesa.Series.Application.UseCases.FetchNextPlayableEpisode do
  @moduledoc "Derive the entry to open after the played file from the series entries."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Domain.Policies.AutoAdvancePolicy
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus

  @spec call(AuthenticatedUser.t(), pos_integer(), pos_integer(), WatchedEntriesReader.adapter()) ::
          {:ok, EntryStatus.t()}
          | {:error, :forbidden | :not_found | :unavailable | :part_unavailable}
  def call(actor, episode_id, file_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         {:ok, played} <- reader.fetch_played_entries(episode_id, file_id),
         {:ok, entries} <- reader.list_entries(actor.id, {:series_of, episode_id}) do
      AutoAdvancePolicy.call(entries, played)
    end
  end
end

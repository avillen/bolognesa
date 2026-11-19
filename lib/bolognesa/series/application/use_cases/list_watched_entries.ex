defmodule Bolognesa.Series.Application.UseCases.ListWatchedEntries do
  @moduledoc "Read the authenticated account's watched entries without inventory filtering."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus

  @spec call(
          AuthenticatedUser.t() | nil,
          WatchedEntriesReader.scope(),
          WatchedEntriesReader.adapter()
        ) ::
          {:ok, [SeasonEntryStatus.t()]} | {:error, :forbidden | :unavailable}
  def call(actor, scope, reader) do
    with :ok <- Accounts.authorize(actor, :admin) do
      with {:ok, entries} <- reader.list_entries(actor.id, scope) do
        {:ok, Enum.filter(entries, & &1.last_watched_at)}
      end
    end
  end
end

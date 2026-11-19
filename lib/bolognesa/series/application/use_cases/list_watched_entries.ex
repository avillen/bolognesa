defmodule Bolognesa.Series.Application.UseCases.ListWatchedEntries do
  @moduledoc "Read the authenticated account's watched entries without inventory filtering."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Domain.ReadModels.WatchedEntry

  @spec call(
          AuthenticatedUser.t() | nil,
          WatchedEntriesReader.scope(),
          WatchedEntriesReader.adapter()
        ) ::
          {:ok, [WatchedEntry.t()]} | {:error, :forbidden | :unavailable}
  def call(actor, scope, reader) do
    with :ok <- Accounts.authorize(actor, :admin) do
      reader.list_watched_entries(actor.id, scope)
    end
  end
end

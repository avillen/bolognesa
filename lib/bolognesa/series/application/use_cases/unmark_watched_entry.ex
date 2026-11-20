defmodule Bolognesa.Series.Application.UseCases.UnmarkWatchedEntry do
  @moduledoc "Remove one entry from the authenticated account's watched entries."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  @spec call(AuthenticatedUser.t() | nil, Entry.t(), WatchedEntriesRepository.adapter()) ::
          :ok | {:error, :forbidden | :unavailable}
  def call(actor, entry, repository) do
    with :ok <- Accounts.authorize(actor, :admin), do: repository.delete(actor.id, entry)
  end
end

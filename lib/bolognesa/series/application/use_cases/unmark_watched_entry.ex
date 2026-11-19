defmodule Bolognesa.Series.Application.UseCases.UnmarkWatchedEntry do
  @moduledoc "Remove one season entry from the authenticated account's watched entries."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Repositories.WatchedEntriesRepository
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  @spec call(AuthenticatedUser.t() | nil, SeasonEntry.t(), WatchedEntriesRepository.adapter()) ::
          :ok | {:error, :forbidden | :unavailable}
  def call(actor, entry, repository) do
    with :ok <- Accounts.authorize(actor, :admin), do: repository.delete(actor.id, entry)
  end
end

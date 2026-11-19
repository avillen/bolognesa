defmodule Bolognesa.Series.Application.UseCases.FetchContinueTarget do
  @moduledoc "Derive the authenticated account's Continue target for one series."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Domain.Policies.ContinueTargetPolicy
  alias Bolognesa.Series.Domain.ReadModels.ContinueTarget
  alias Bolognesa.Series.Domain.ReadModels.Series

  @spec call(AuthenticatedUser.t() | nil, Series.id(), WatchedEntriesReader.adapter()) ::
          {:ok, ContinueTarget.t() | nil} | {:error, :forbidden | :unavailable}
  def call(actor, series_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         {:ok, entries} <- reader.list_continue_entries(actor.id, series_id) do
      {:ok, ContinueTargetPolicy.call(entries)}
    end
  end
end

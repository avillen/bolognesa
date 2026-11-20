defmodule Bolognesa.Series.Application.UseCases.ListRecentSeries do
  @moduledoc "Authorized, bounded lookup of the account's recently watched series with their Continue targets."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.ReadQuery
  alias Bolognesa.Series.Application.Ports.Readers.WatchedEntriesReader
  alias Bolognesa.Series.Domain.Policies.ContinueTargetPolicy
  alias Bolognesa.Series.Domain.ReadModels.ContinueTarget
  alias Bolognesa.Series.Domain.ReadModels.Series

  @type result ::
          {:ok, [{Series.t(), ContinueTarget.t()}]}
          | {:error, :forbidden | :invalid_query | :unavailable}

  @spec call(AuthenticatedUser.t() | nil, pos_integer() | nil, WatchedEntriesReader.adapter()) ::
          result()
  def call(actor, library_id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_optional_id(library_id),
         {:ok, recent} <- reader.list_recent_series(actor.id, library_id) do
      targets =
        for {series, entries} <- recent,
            target = ContinueTargetPolicy.call(entries),
            do: {series, target}

      {:ok, targets}
    end
  end
end

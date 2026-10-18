defmodule Bolognesa.Series.Application.UseCases.FetchSeriesSeason do
  @moduledoc "Authorize a season lookup for a manual episode selection."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Series.Domain.ValueObjects.SeasonDetails

  @spec call(AuthenticatedUser.t(), pos_integer(), non_neg_integer(), SeriesProvider.adapter()) ::
          {:ok, SeasonDetails.t()}
          | :not_found
          | {:error, :forbidden | :invalid_selection | SeriesProvider.reason()}
  def call(actor, id, number, provider) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- valid_ids(id, number),
         {:ok, season} <- provider.season(id, number) do
      {:ok, season}
    else
      {:error, :not_found} -> :not_found
      error -> error
    end
  end

  defp valid_ids(id, number)
       when is_integer(id) and id > 0 and is_integer(number) and number >= 0, do: :ok

  defp valid_ids(_, _), do: {:error, :invalid_selection}
end

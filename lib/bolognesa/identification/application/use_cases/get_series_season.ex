defmodule Bolognesa.Identification.Application.UseCases.GetSeriesSeason do
  @moduledoc "Authorize a season lookup for a manual episode selection."
  alias Bolognesa.Identification.Application.Ports.Providers.SeriesProvider
  alias Bolognesa.Identification.Domain.ValueObjects.Series.SeasonDetails
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor

  @spec call(Actor.t(), pos_integer(), non_neg_integer(), SeriesProvider.adapter()) ::
          {:ok, SeasonDetails.t()}
          | {:error, :forbidden | :invalid_selection | SeriesProvider.reason()}
  def call(actor, id, number, provider) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_ids(id, number),
         do: provider.season(id, number)
  end

  defp valid_ids(id, number)
       when is_integer(id) and id > 0 and is_integer(number) and number >= 0, do: :ok

  defp valid_ids(_, _), do: {:error, :invalid_selection}
end

defmodule Bolognesa.Catalog.Application.UseCases.GetSeries do
  @moduledoc "Authorize one series and its identified seasons."
  alias Bolognesa.Catalog.Application.Dto.SeriesDetail
  alias Bolognesa.Catalog.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Catalog.Domain.Series
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec call(Actor.t(), Series.id(), SeriesReader.adapter()) ::
          {:ok, SeriesDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, id, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- valid_id(id),
         {:ok, result} <- reader.get_series(id) do
      {:ok, SeriesDetail.from_domain(result)}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: {:error, :not_found}
end

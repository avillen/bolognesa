defmodule Bolognesa.Series.Application.UseCases.GetSeries do
  @moduledoc "Authorize one series and its identified seasons."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.UseCases.GetSeries.Response, as: SeriesDetail
  alias Bolognesa.Series.Domain.ReadModels.Series

  @spec call(AuthenticatedUser.t(), Series.id(), SeriesReader.adapter()) ::
          {:ok, SeriesDetail.t()}
          | {:error, :forbidden | :not_found | :unavailable | :too_many_seasons}
  def call(actor, id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- valid_id(id),
         {:ok, result} <- reader.get_series(id) do
      {:ok, SeriesDetail.from_domain(result)}
    end
  end

  defp valid_id(id) when is_integer(id) and id > 0, do: :ok
  defp valid_id(_), do: {:error, :not_found}
end

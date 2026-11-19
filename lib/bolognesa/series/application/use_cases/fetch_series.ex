defmodule Bolognesa.Series.Application.UseCases.FetchSeries do
  @moduledoc "Authorize one series and its identified seasons."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.ReadQuery
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.UseCases.FetchSeries.Response, as: SeriesDetail
  alias Bolognesa.Series.Domain.ReadModels.Series

  @spec call(AuthenticatedUser.t(), Series.id(), SeriesReader.adapter()) ::
          {:ok, SeriesDetail.t()}
          | {:error, :forbidden | :not_found | :unavailable | :too_many_seasons}
  def call(actor, id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_id(id),
         {:ok, result} <- reader.fetch_series(id) do
      {:ok, SeriesDetail.from_domain(result)}
    end
  end
end

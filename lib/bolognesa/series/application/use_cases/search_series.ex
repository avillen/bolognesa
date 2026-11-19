defmodule Bolognesa.Series.Application.UseCases.SearchSeries do
  @moduledoc "Authorize and bound the series catalog search."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.ReadQuery
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.UseCases.SearchSeries.Response, as: SeriesPage

  @spec call(
          AuthenticatedUser.t(),
          String.t(),
          SeriesReader.page_number(),
          SeriesReader.adapter(),
          SeriesReader.library_id()
        ) ::
          {:ok, SeriesPage.t()}
          | {:error, :forbidden | :invalid_query | :invalid_page | :unavailable}
  def call(actor, query, page, reader, library_id \\ nil) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- ReadQuery.valid_optional_id?(library_id) || {:error, :invalid_query},
         true <- ReadQuery.valid_text?(query) || {:error, :invalid_query},
         true <- ReadQuery.valid_page?(page) || {:error, :invalid_page},
         {:ok, result} <- reader.list_series(String.trim(query), page, library_id) do
      {:ok, SeriesPage.from_domain(result)}
    end
  end
end

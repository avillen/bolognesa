defmodule Bolognesa.Series.Application.UseCases.SearchSeries do
  @moduledoc "Authorize and bound the series catalog search."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Series.Application.Ports.Readers.SeriesReader
  alias Bolognesa.Series.Application.UseCases.SearchSeries.Response, as: SeriesPage

  @spec call(
          Actor.t(),
          String.t(),
          SeriesReader.page_number(),
          SeriesReader.adapter(),
          SeriesReader.library_id()
        ) ::
          {:ok, SeriesPage.t()}
          | {:error, :forbidden | :invalid_query | :invalid_page | :unavailable}
  def call(actor, query, page, reader, library_id \\ nil) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- validate_library(library_id),
         :ok <- query_valid(query),
         :ok <- page_valid(page),
         {:ok, result} <- reader.list_series(String.trim(query), page, library_id) do
      {:ok, SeriesPage.from_domain(result)}
    end
  end

  defp validate_library(nil), do: :ok
  defp validate_library(id) when is_integer(id) and id > 0, do: :ok
  defp validate_library(_), do: {:error, :invalid_query}

  defp query_valid(query) when is_binary(query),
    do:
      if(String.valid?(query) and byte_size(query) <= 256,
        do: :ok,
        else: {:error, :invalid_query}
      )

  defp query_valid(_), do: {:error, :invalid_query}
  defp page_valid(page) when is_integer(page) and page in 1..100_000, do: :ok
  defp page_valid(_), do: {:error, :invalid_page}
end

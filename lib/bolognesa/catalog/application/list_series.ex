defmodule Bolognesa.Catalog.Application.ListSeries do
  @moduledoc "Authorize and bound the series catalog search."
  alias Bolognesa.Catalog.Application.Dto.{SeriesListItem, SeriesPage}
  alias Bolognesa.Catalog.Application.Ports.SeriesReader
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Actor

  @spec call(Actor.t(), binary(), SeriesReader.page_number(), SeriesReader.adapter()) ::
          {:ok, SeriesPage.t()}
          | {:error, :forbidden | :invalid_query | :invalid_page | :unavailable}
  def call(actor, query, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- query_valid(query),
         :ok <- page_valid(page),
         {:ok, {rows, total}} <- reader.list_series(String.trim(query), page) do
      {:ok, %SeriesPage{items: Enum.map(rows, &SeriesListItem.from_domain/1), total: total}}
    end
  end

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

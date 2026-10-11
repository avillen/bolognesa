defmodule Bolognesa.Catalog.Application.ListMovies do
  @moduledoc "Authorize and bound a movie catalog search."
  alias Bolognesa.Catalog.Application.Dto.{MovieListItem, MoviePage}
  alias Bolognesa.Catalog.Application.Ports.CatalogReader
  alias Bolognesa.Identity

  @spec call(
          Bolognesa.Identity.Domain.Actor.t(),
          binary(),
          CatalogReader.page_number(),
          CatalogReader.adapter()
        ) ::
          {:ok, MoviePage.t()} | {:error, :forbidden | :invalid_query | :unavailable}
  def call(actor, query, page, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate(query, page),
         {:ok, {rows, total}} <- reader.list_movies(String.trim(query), page) do
      {:ok, %MoviePage{items: Enum.map(rows, &MovieListItem.from_domain/1), total: total}}
    end
  end

  defp validate(query, page)
       when is_binary(query) and is_integer(page) and page > 0 and page <= 100_000 do
    if String.valid?(query) and byte_size(query) <= 256, do: :ok, else: {:error, :invalid_query}
  end

  defp validate(_, _), do: {:error, :invalid_query}
end

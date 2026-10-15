defmodule Bolognesa.Catalog.Application.UseCases.ListMovies do
  @moduledoc "Authorize and bound a movie catalog search."
  alias Bolognesa.Catalog.Application.Dto.MoviePage
  alias Bolognesa.Catalog.Application.Ports.Readers.MoviesReader
  alias Bolognesa.Identity

  @spec call(
          Bolognesa.Identity.Domain.Entities.Actor.t(),
          String.t(),
          MoviesReader.page_number(),
          MoviesReader.adapter(),
          MoviesReader.library_id()
        ) ::
          {:ok, MoviePage.t()} | {:error, :forbidden | :invalid_query | :unavailable}
  def call(actor, query, page, reader, library_id \\ nil) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate_library(library_id),
         :ok <- validate(query, page),
         {:ok, result} <- reader.list_movies(String.trim(query), page, library_id) do
      {:ok, MoviePage.from_domain(result)}
    end
  end

  defp validate_library(nil), do: :ok
  defp validate_library(id) when is_integer(id) and id > 0, do: :ok
  defp validate_library(_), do: {:error, :invalid_query}

  defp validate(query, page)
       when is_binary(query) and is_integer(page) and page > 0 and page <= 100_000 do
    if String.valid?(query) and byte_size(query) <= 256, do: :ok, else: {:error, :invalid_query}
  end

  defp validate(_, _), do: {:error, :invalid_query}
end

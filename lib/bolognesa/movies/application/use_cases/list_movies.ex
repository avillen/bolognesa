defmodule Bolognesa.Movies.Application.UseCases.ListMovies do
  @moduledoc "Authorize and bound a movie catalog search."
  alias Bolognesa.Accounts
  alias Bolognesa.Movies.Application.Ports.Readers.MoviesReader
  alias Bolognesa.Movies.Application.UseCases.ListMovies.Response, as: MoviePage
  alias Bolognesa.ReadQuery

  @spec call(
          Bolognesa.Accounts.Domain.Entities.AuthenticatedUser.t(),
          String.t(),
          MoviesReader.page_number(),
          MoviesReader.adapter(),
          MoviesReader.library_id()
        ) ::
          {:ok, MoviePage.t()} | {:error, :forbidden | :invalid_query | :unavailable}
  def call(actor, query, page, reader, library_id \\ nil) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate(query, page, library_id),
         {:ok, result} <- reader.list_movies(String.trim(query), page, library_id) do
      {:ok, MoviePage.from_domain(result)}
    end
  end
end

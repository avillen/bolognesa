defmodule Bolognesa.Movies.Application.UseCases.GetMovie do
  @moduledoc "Authorize a movie detail read."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Movies.Application.Ports.Readers.MoviesReader
  alias Bolognesa.Movies.Application.UseCases.GetMovie.Response, as: MovieDetail
  alias Bolognesa.Movies.Domain.ReadModels.Movie
  alias Bolognesa.ReadQuery

  @spec call(AuthenticatedUser.t(), Movie.id(), MoviesReader.adapter()) ::
          {:ok, MovieDetail.t()}
          | {:error, :forbidden | :not_found | :unavailable | :too_many_versions}
  def call(actor, id, reader) do
    with :ok <- Accounts.authorize(actor, :admin),
         :ok <- ReadQuery.validate_id(id),
         {:ok, result} <- reader.get_movie(id) do
      {:ok, MovieDetail.from_domain(result)}
    end
  end
end

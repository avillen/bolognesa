defmodule Bolognesa.Catalog.Application.UseCases.GetMovie do
  @moduledoc "Authorize a movie detail read."
  alias Bolognesa.Catalog.Application.Dto.MovieDetail
  alias Bolognesa.Catalog.Application.Ports.Readers.MoviesReader
  alias Bolognesa.Identity

  @spec call(Bolognesa.Identity.Domain.Entities.Actor.t(), pos_integer(), MoviesReader.adapter()) ::
          {:ok, MovieDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, id, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate_id(id),
         {:ok, result} <- reader.get_movie(id) do
      {:ok, MovieDetail.from_domain(result)}
    end
  end

  defp validate_id(id) when is_integer(id) and id > 0, do: :ok
  defp validate_id(_id), do: {:error, :not_found}
end

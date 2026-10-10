defmodule Bolognesa.Catalog.Application.GetMovie do
  @moduledoc "Authorize a movie detail read."
  alias Bolognesa.Catalog.Application.Dto.{MovieDetail, MovieVersion}
  alias Bolognesa.Catalog.Application.Ports.CatalogReader
  alias Bolognesa.Catalog.Domain.MovieVersion, as: DomainMovieVersion
  alias Bolognesa.Identity

  @spec call(Bolognesa.Identity.Domain.Actor.t(), pos_integer(), CatalogReader.adapter()) ::
          {:ok, MovieDetail.t()} | {:error, :forbidden | :not_found | :unavailable}
  def call(actor, id, reader) do
    with :ok <- Identity.authorize(actor, :admin),
         :ok <- validate_id(id),
         {:ok, {movie, versions}} <- reader.get_movie(id) do
      {:ok, %MovieDetail{movie: movie, versions: Enum.map(versions, &to_movie_version/1)}}
    end
  end

  defp validate_id(id) when is_integer(id) and id > 0, do: :ok
  defp validate_id(_id), do: {:error, :not_found}

  defp to_movie_version(%DomainMovieVersion{} = version) do
    %MovieVersion{
      id: version.id,
      availability: version.availability,
      size_bytes: version.size_bytes,
      origin: version.origin,
      needs_review: version.needs_review?
    }
  end
end

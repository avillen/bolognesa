defmodule Bolognesa.Playback.Infrastructure.Persistence.EctoPlaybackRepository do
  @moduledoc false
  @behaviour Bolognesa.Playback.Application.Ports.PlaybackRepository

  import Ecto.Query

  alias Bolognesa.Catalog.Infrastructure.Persistence.EctoMovieRepository.MovieSchema

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema
  alias Bolognesa.Repo

  @impl true
  def find_source(movie_id, file_id) do
    query =
      from movie in MovieSchema,
        join: identification in IdentificationSchema,
        on: identification.movie_id == movie.id,
        join: file in MediaFileSchema,
        on: file.id == identification.media_file_id,
        join: library in LibrarySchema,
        on: library.id == file.library_id,
        where:
          movie.id == ^movie_id and file.id == ^file_id and
            identification.state in [:automatic, :manual],
        select: %{
          path: library.path,
          relative_path: file.relative_path,
          size_bytes: file.size_bytes,
          modified_at: file.modified_at,
          availability: file.availability
        }

    case Repo.one(query, log: false) do
      nil -> {:error, :not_found}
      %{availability: :missing} -> {:error, :missing}
      %{availability: :available} = source -> {:ok, Map.delete(source, :availability)}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end
end

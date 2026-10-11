defmodule Bolognesa.Playback.Infrastructure.Persistence.EctoPlaybackRepository do
  @moduledoc false
  @behaviour Bolognesa.Playback.Application.Ports.PlaybackRepository

  import Ecto.Query

  alias Bolognesa.Persistence.IdentificationSchema
  alias Bolognesa.Persistence.InspectionSchema
  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema
  alias Bolognesa.Persistence.MovieSchema
  alias Bolognesa.Playback.Domain.Source
  alias Bolognesa.Playback.Domain.TechnicalTrack
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
        left_join: inspection in InspectionSchema,
        on:
          inspection.media_file_id == file.id and inspection.observed_revision == file.revision and
            inspection.state == :succeeded,
        where:
          movie.id == ^movie_id and file.id == ^file_id and
            identification.state in [:automatic, :manual],
        select: %{
          path: library.path,
          relative_path: file.relative_path,
          size_bytes: file.size_bytes,
          modified_at: file.modified_at,
          availability: file.availability,
          revision: file.revision,
          format: inspection.format,
          duration_ms: inspection.duration_ms,
          tracks: inspection.tracks
        }

    case Repo.one(query, log: false) do
      nil ->
        {:error, :not_found}

      %{availability: :missing} ->
        {:error, :missing}

      %{availability: :available} = source ->
        {:ok,
         %Source{
           path: source.path,
           relative_path: source.relative_path,
           size_bytes: source.size_bytes,
           modified_at: source.modified_at,
           revision: source.revision,
           format: source.format,
           duration_ms: source.duration_ms,
           tracks: tracks(source.tracks)
         }}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  defp tracks(%{"items" => items}) when is_list(items) do
    Enum.flat_map(items, fn row ->
      case row do
        %{"kind" => kind, "codec" => codec} when kind in ["video", "audio", "subtitle"] ->
          [%TechnicalTrack{kind: track_kind(kind), codec: codec}]

        _ ->
          []
      end
    end)
  end

  defp tracks(_), do: []

  defp track_kind("video"), do: :video
  defp track_kind("audio"), do: :audio
  defp track_kind("subtitle"), do: :subtitle
end

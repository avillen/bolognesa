defmodule Bolognesa.Music.StaleCountTracksReader do
  @moduledoc false
  @behaviour Bolognesa.Music.Application.Ports.Readers.TracksReader
  alias Bolognesa.Music.Domain.ReadModels.{TrackPage, TrackRow}
  @impl true
  def list_tracks(_, _, _), do: {:error, :unavailable}
  @impl true
  def list_album_tracks(_, _, _, _, _) do
    items =
      for id <- 1..501,
          do: %TrackRow{
            id: id,
            file_id: id,
            title: "Song #{id}",
            state: :ready,
            duration_ms: 1000
          }

    {:ok, %TrackPage{total: 500, items: items}}
  end
end

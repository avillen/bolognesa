defmodule BolognesaWeb.Music.Index.State.Track do
  @moduledoc "Localized music list presentation."
  use Gettext, backend: BolognesaWeb.Gettext
  alias Bolognesa.Music.Application.Dto

  defstruct [
    :id,
    :track_id,
    :title,
    :artist,
    :album,
    :duration,
    :state,
    :state_label,
    :disc_number,
    :track_number
  ]

  @type t :: %__MODULE__{
          id: pos_integer(),
          track_id: pos_integer() | nil,
          title: String.t(),
          artist: String.t(),
          album: String.t(),
          duration: String.t(),
          state: atom(),
          state_label: String.t(),
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil
        }
  @spec from_dto(Dto.Track.t()) :: t()
  def from_dto(track),
    do: %__MODULE__{
      id: track.file_id,
      track_id: track.id,
      title: track.title,
      artist: track.artist || gettext("Artista desconocido"),
      album: track.album || gettext("Sin álbum"),
      duration: duration(track.duration_ms),
      state: track.state,
      state_label: label(track.state),
      disc_number: track.disc_number,
      track_number: track.track_number
    }

  defp duration(nil), do: "—"

  defp duration(ms) do
    seconds = div(ms, 1000)

    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp label(:ready), do: gettext("Disponible")
  defp label(:pending), do: gettext("Procesando audio")
  defp label(:inspection_failed), do: gettext("Error de análisis de audio")
  defp label(:import_failed), do: gettext("Error al importar la canción")
end

defmodule Bolognesa.Music.Domain.ValueObjects.TrackMetadata do
  @moduledoc "Musical metadata with safe display fallback and raw grouping parent."
  alias Bolognesa.Music.Domain.ValueObjects.Observation

  @type t :: %__MODULE__{
          title: String.t(),
          artist: String.t() | nil,
          album_artist: String.t() | nil,
          album: String.t() | nil,
          source_parent: binary(),
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil,
          year: pos_integer() | nil
        }

  defstruct [
    :title,
    :artist,
    :album_artist,
    :album,
    :source_parent,
    :disc_number,
    :track_number,
    :year
  ]

  @spec from_observation(Observation.t()) :: t()
  def from_observation(observation) do
    tags = observation.music_tags
    parts = :binary.split(observation.relative_path, "/", [:global])
    filename = List.last(parts)

    %__MODULE__{
      title: tags.title || fallback(filename),
      artist: tags.artist,
      album_artist: tags.album_artist || tags.artist,
      album: tags.album,
      source_parent: parts |> Enum.drop(-1) |> Enum.join("/"),
      disc_number: tags.disc_number,
      track_number: tags.track_number,
      year: tags.year
    }
  end

  defp fallback(filename) do
    filename |> safe_utf8() |> Path.rootname()
  end

  defp safe_utf8(<<>>), do: ""
  defp safe_utf8(<<codepoint::utf8, rest::binary>>), do: <<codepoint::utf8>> <> safe_utf8(rest)
  defp safe_utf8(<<_invalid, rest::binary>>), do: "�" <> safe_utf8(rest)
end

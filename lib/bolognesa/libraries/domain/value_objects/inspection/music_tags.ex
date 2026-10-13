defmodule Bolognesa.Libraries.Domain.ValueObjects.Inspection.MusicTags do
  @moduledoc "Allowlisted, bounded local music observations."
  defstruct [:title, :artist, :album_artist, :album, :disc_number, :track_number, :year]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          artist: String.t() | nil,
          album_artist: String.t() | nil,
          album: String.t() | nil,
          disc_number: pos_integer() | nil,
          track_number: pos_integer() | nil,
          year: pos_integer() | nil
        }
  @type raw_tags :: map() | list() | String.t() | nil
  @spec from_raw(raw_tags()) :: t()
  def from_raw(raw) when is_map(raw) do
    tags = Map.new(raw, fn {key, value} -> {key_name(key), text(value)} end)

    %__MODULE__{
      title: tags["title"],
      artist: tags["artist"],
      album: tags["album"],
      album_artist: tags["album_artist"] || tags["albumartist"],
      disc_number: number(tags["disc"] || tags["discnumber"]),
      track_number: number(tags["track"] || tags["tracknumber"]),
      year: year(tags["date"] || tags["year"])
    }
  end

  def from_raw(_raw), do: %__MODULE__{}

  defp key_name(key) when is_binary(key) do
    if String.valid?(key), do: String.downcase(key), else: ""
  end

  defp key_name(_key), do: ""

  defp text(value) when is_binary(value) and byte_size(value) <= 512 do
    if String.valid?(value), do: nonblank(String.trim(value)), else: nil
  end

  defp text(_value), do: nil
  defp nonblank(""), do: nil
  defp nonblank(value), do: value
  defp number(nil), do: nil

  defp number(value) do
    case Regex.run(~r/\A([0-9]{1,4})(?:\/([0-9]{1,5}))?\z/, value) do
      [_, number] -> positive(number)
      [_, number, total] -> if positive(total), do: positive(number), else: nil
      _ -> nil
    end
  end

  defp positive(text) do
    {value, ""} = Integer.parse(text)
    if value in 1..99_999, do: value, else: nil
  end

  defp year(nil), do: nil

  defp year(value) do
    case Regex.run(~r/\A([1-9][0-9]{3})(?:-[0-9]{2}-[0-9]{2})?\z/, value) do
      [_, year] -> String.to_integer(year)
      _ -> nil
    end
  end
end

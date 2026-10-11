defmodule Bolognesa.Identification.Domain.ValueObjects.Movies.TitleHint do
  @moduledoc "Derives a bounded movie title and optional year from a filename."

  @release_words ~w(1080p 2160p 720p 480p bluray brrip webrip web-dl dvdrip hdrip h264 h265 x264 x265 hevc ac3 dts remux)

  @spec from_path(binary()) ::
          {:ok, %{title: binary(), year: integer() | nil}} | {:error, :unusable_name}
  def from_path(path) when is_binary(path) do
    if String.valid?(path) do
      path
      |> Path.basename()
      |> Path.rootname()
      |> parse_name()
    else
      {:error, :unusable_name}
    end
  end

  def from_path(_path), do: {:error, :unusable_name}

  defp parse_name(stem) do
    {title_part, year} = split_year(stem)

    title =
      title_part
      |> String.replace(~r/\bweb[-_. ]dl\b/iu, " ")
      |> String.replace(~r/[._-]+/u, " ")
      |> String.replace(~r/[()[\]{}]+/u, " ")
      |> String.split(~r/\s+/u, trim: true)
      |> Enum.reject(&(String.downcase(&1) in @release_words))
      |> Enum.join(" ")
      |> String.trim()

    if title == "" or byte_size(title) > 256,
      do: {:error, :unusable_name},
      else: {:ok, %{title: title, year: year}}
  end

  defp split_year(stem) do
    case Regex.run(~r/^(.*?)[._\s(\[]((?:19|20)\d{2})(?:[.)\]\s]|$)/u, stem) do
      [_, prefix, year] -> {prefix, String.to_integer(year)}
      _ -> {stem, nil}
    end
  end
end

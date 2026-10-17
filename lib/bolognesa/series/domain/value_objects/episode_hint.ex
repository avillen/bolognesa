defmodule Bolognesa.Series.Domain.ValueObjects.EpisodeHint do
  @moduledoc "Derives series and a bounded episode selection from a relative filename."
  alias Bolognesa.Series.Domain.ValueObjects.TitleHint

  @marker ~r/(?<![a-z0-9])(?:s\d+e\d+|\d+x\d+)/iu
  @parts ~r/\A(?:s(?<season>\d+)e|(?<alternate>\d+)x)(?<episodes>\d+(?:(?:e|x)\d+|-(?:e)?\d+)*)(?<remainder>.*)\z/iu
  @folder ~r/\A(?:season[ ._-]*|temporada[ ._-]*|s)(\d+)\z/iu

  @type t :: %__MODULE__{
          title: binary(),
          year: integer() | nil,
          season_number: non_neg_integer(),
          episode_numbers: [pos_integer()]
        }
  @type error :: :unusable_name | :ambiguous_name | :invalid_episode_numbers | :too_many_episodes

  defstruct [:title, :year, :season_number, :episode_numbers]

  @spec from_path(binary()) :: {:ok, t()} | {:error, error()}
  def from_path(path) when is_binary(path) do
    if String.valid?(path) and byte_size(path) <= 4096 and Path.type(path) == :relative,
      do: parse(path),
      else: {:error, :unusable_name}
  end

  def from_path(_), do: {:error, :unusable_name}

  defp parse(path) do
    stem = path |> Path.basename() |> Path.rootname()

    with {:ok, offset} <- marker(stem),
         prefix = binary_part(stem, 0, offset),
         suffix = binary_part(stem, offset, byte_size(stem) - offset),
         {:ok, season, numbers} <- parse_parts(suffix),
         :ok <- check_folder(path, season),
         {:ok, title} <- title_hint(prefix, path) do
      {:ok,
       %__MODULE__{
         title: title.title,
         year: title.year,
         season_number: season,
         episode_numbers: numbers
       }}
    end
  end

  defp marker(stem) do
    case Regex.scan(@marker, stem, return: :index) do
      [[{offset, _}]] -> {:ok, offset}
      [] -> {:error, :unusable_name}
      _ -> {:error, :ambiguous_name}
    end
  end

  defp parse_parts(suffix) do
    case Regex.named_captures(@parts, suffix) do
      %{
        "season" => season,
        "alternate" => alternate,
        "episodes" => episodes,
        "remainder" => remainder
      } ->
        parsed_selection(season, alternate, episodes, remainder)

      _ ->
        {:error, :unusable_name}
    end
  end

  defp parsed_selection(season, alternate, episodes, remainder) do
    season_number = season |> season_text(alternate) |> String.to_integer()

    with :ok <- valid_remainder(remainder),
         {:ok, numbers} <- episode_numbers(episodes),
         do: {:ok, season_number, numbers}
  end

  defp season_text("", alternate), do: alternate
  defp season_text(season, _alternate), do: season

  defp valid_remainder(""), do: :ok

  defp valid_remainder(remainder) do
    if Regex.match?(~r/\A(?:[\s._\[]|-(?![exs\d]))/iu, remainder),
      do: :ok,
      else: {:error, :ambiguous_name}
  end

  defp episode_numbers(text) do
    cond do
      Regex.match?(~r/\A\d+\z/, text) ->
        validate_numbers([String.to_integer(text)])

      Regex.match?(~r/\A\d+-(?:e)?\d+\z/iu, text) ->
        expand_range(text)

      Regex.match?(~r/\A\d+(?:e\d+)+\z/iu, text) or Regex.match?(~r/\A\d+(?:x\d+)+\z/iu, text) ->
        text |> String.split(~r/[ex]/iu) |> Enum.map(&String.to_integer/1) |> validate_numbers()

      true ->
        {:error, :invalid_episode_numbers}
    end
  end

  defp expand_range(text) do
    [first, last] = Regex.scan(~r/\d+/, text) |> Enum.map(fn [n] -> String.to_integer(n) end)

    cond do
      first <= 0 or last < first -> {:error, :invalid_episode_numbers}
      last - first + 1 > 100 -> {:error, :too_many_episodes}
      true -> {:ok, Enum.to_list(first..last)}
    end
  end

  defp validate_numbers(numbers) do
    cond do
      length(numbers) > 100 ->
        {:error, :too_many_episodes}

      Enum.any?(numbers, &(&1 <= 0)) or Enum.uniq(numbers) != numbers ->
        {:error, :invalid_episode_numbers}

      true ->
        {:ok, numbers}
    end
  end

  defp check_folder(path, season) do
    case folder_number(Path.basename(Path.dirname(path))) do
      nil -> :ok
      ^season -> :ok
      _ -> {:error, :ambiguous_name}
    end
  end

  defp folder_number(folder) do
    case Regex.run(@folder, folder) do
      [_, number] -> String.to_integer(number)
      _ -> special_number(folder)
    end
  end

  defp special_number(folder),
    do: if(String.downcase(folder) in ["especiales", "specials"], do: 0, else: nil)

  defp title_hint(prefix, path) do
    cleaned = String.trim(prefix)

    if Regex.match?(~r/\A[\s._-]*\z/u, prefix),
      do: folder_title(path),
      else: TitleHint.from_path(cleaned <> ".mkv")
  end

  defp folder_title(path) do
    parent = Path.dirname(path)
    folder = Path.basename(parent)
    directory = if is_nil(folder_number(folder)), do: parent, else: Path.dirname(parent)

    case Path.basename(directory) do
      "." -> {:error, :unusable_name}
      title -> TitleHint.from_path(title <> ".mkv")
    end
  end
end

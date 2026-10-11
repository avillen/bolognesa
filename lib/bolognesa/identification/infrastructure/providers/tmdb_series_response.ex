defmodule Bolognesa.Identification.Infrastructure.Providers.TmdbSeriesResponse do
  @moduledoc false
  alias Bolognesa.Identification.Domain.{
    EpisodeDetails,
    SeasonDetails,
    SeriesCandidate,
    SeriesDetails
  }

  @spec search(binary()) :: {:ok, [SeriesCandidate.t()]} | {:error, :invalid_response}
  def search(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => results}} when is_list(results) ->
        candidates =
          results
          |> Enum.filter(&is_map/1)
          |> Enum.reject(&(&1["adult"] == true))
          |> Enum.flat_map(&candidate/1)
          |> Enum.take(5)

        {:ok, candidates}

      _ ->
        {:error, :invalid_response}
    end
  end

  @spec details(binary()) :: {:ok, SeriesDetails.t()} | {:error, :invalid_response}
  def details(body) do
    with {:ok, raw} when is_map(raw) <- Jason.decode(body),
         {:ok, result} <- SeriesDetails.new(attrs(raw)) do
      {:ok, result}
    else
      _ -> {:error, :invalid_response}
    end
  end

  @spec season(binary(), pos_integer(), non_neg_integer()) ::
          {:ok, SeasonDetails.t()} | {:error, :invalid_response}
  def season(body, series_id, season_number) do
    with {:ok, raw} when is_map(raw) <- Jason.decode(body),
         true <- raw["season_number"] == season_number,
         episodes when is_list(episodes) <- raw["episodes"],
         {:ok, values} <- episodes(episodes),
         season = %SeasonDetails{
           provider_id: raw["id"],
           series_provider_id: series_id,
           number: season_number,
           title: optional_text(raw["name"], 256),
           poster_path: SeriesCandidate.image_path(raw["poster_path"]),
           episodes: values
         },
         {:ok, season} <- SeasonDetails.new(Map.from_struct(season)) do
      {:ok, season}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp candidate(raw) do
    case SeriesCandidate.new(attrs(raw)) do
      {:ok, candidate} -> [candidate]
      _ -> []
    end
  end

  defp attrs(raw),
    do: %{
      provider_id: raw["id"],
      title: raw["name"],
      year: year(raw["first_air_date"]),
      poster_path: raw["poster_path"],
      backdrop_path: raw["backdrop_path"],
      overview: raw["overview"]
    }

  defp year(text) do
    case date(text) do
      %Date{year: year} -> year
      _ -> nil
    end
  end

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date(_), do: nil

  defp episodes(raw) do
    values = Enum.map(raw, &episode/1)
    if Enum.any?(values, &is_nil/1), do: {:error, :invalid_response}, else: {:ok, values}
  end

  defp episode(raw) when is_map(raw),
    do: %EpisodeDetails{
      provider_id: raw["id"],
      season_number: raw["season_number"],
      number: raw["episode_number"],
      title: raw["name"],
      overview: optional_text(raw["overview"], 2000),
      air_date: date(raw["air_date"]),
      still_path: SeriesCandidate.image_path(raw["still_path"])
    }

  defp episode(_), do: nil

  defp optional_text(value, max) when is_binary(value),
    do: if(String.valid?(value) and byte_size(value) <= max, do: value, else: nil)

  defp optional_text(_, _), do: nil
end

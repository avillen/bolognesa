defmodule Bolognesa.Identification.Infrastructure.Providers.TmdbResponse do
  @moduledoc false

  alias Bolognesa.Identification.Domain.{MovieCandidate, MovieDetails}

  @spec search(binary()) :: {:ok, [MovieCandidate.t()]} | {:error, :invalid_response}
  def search(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => results}} when is_list(results) ->
        {:ok, parse_candidates(results)}

      _ ->
        {:error, :invalid_response}
    end
  end

  def search(_body), do: {:error, :invalid_response}

  @spec details(binary()) :: {:ok, MovieDetails.t()} | {:error, :invalid_response}
  def details(body) when is_binary(body) do
    with {:ok, raw} when is_map(raw) <- Jason.decode(body),
         {:ok, value} <- MovieDetails.new(attrs(raw)) do
      {:ok, value}
    else
      _ -> {:error, :invalid_response}
    end
  end

  def details(_body), do: {:error, :invalid_response}

  defp parse_candidates(results) do
    results
    |> Enum.filter(&is_map/1)
    |> Enum.reject(&(&1["adult"] == true))
    |> Enum.reduce([], fn raw, acc ->
      case candidate(raw) do
        {:ok, value} -> [value | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()
    |> Enum.take(5)
  end

  defp candidate(raw) when is_map(raw), do: MovieCandidate.new(attrs(raw))
  defp candidate(_raw), do: {:error, :invalid_candidate}

  defp attrs(raw) do
    %{
      provider_id: raw["id"],
      title: raw["title"],
      original_title: raw["original_title"],
      year: year(raw["release_date"]),
      overview: raw["overview"],
      poster_path: raw["poster_path"],
      backdrop_path: raw["backdrop_path"]
    }
  end

  defp year(<<year::binary-size(4), "-", _rest::binary>>) do
    case Integer.parse(year) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp year(_date), do: nil
end

defmodule Bolognesa.Series.Domain.Policies.SeriesMatch do
  @moduledoc "Selects only a unique exact series candidate."
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeHint
  alias Bolognesa.Series.Domain.ValueObjects.SeriesCandidate

  @spec select(EpisodeHint.t(), [SeriesCandidate.t()]) ::
          {:ok, SeriesCandidate.t()} | {:error, :ambiguous_series | :no_match}
  def select(hint, candidates) do
    exact =
      Enum.filter(candidates, fn candidate ->
        normalize(candidate.title) == normalize(hint.title) and
          (is_nil(hint.year) or candidate.year == hint.year)
      end)

    case exact do
      [candidate] -> {:ok, candidate}
      [] -> {:error, :no_match}
      _ -> {:error, :ambiguous_series}
    end
  end

  defp normalize(title),
    do:
      title
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[^a-z0-9]/u, "")
end

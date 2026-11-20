defmodule Bolognesa.Series.Domain.Policies.ContinueTargetPolicy do
  @moduledoc """
  Chooses the Continue target from the regular entries (season 0 excluded) in series order.

  Start at the first entry when nothing is watched. Otherwise continue at the entry
  after the most recently watched one, with ties going to the furthest entry, even
  when it is unavailable. Replay from the first entry when no available entry follows.
  """
  alias Bolognesa.Series.Domain.ReadModels.ContinueTarget
  alias Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus

  @spec call([SeasonEntryStatus.t()]) :: ContinueTarget.t() | nil
  def call(entries) do
    entries |> Enum.reject(&(&1.season_number == 0)) |> choose()
  end

  defp choose([first | _] = entries) do
    case last_watched_index(entries) do
      nil -> %ContinueTarget{action: :start, entry: first}
      index -> after_watched(first, Enum.drop(entries, index + 1))
    end
  end

  defp choose([]), do: nil

  defp after_watched(first, [next | _] = rest) do
    if Enum.any?(rest, & &1.available?),
      do: %ContinueTarget{action: :continue, entry: next},
      else: %ContinueTarget{action: :replay, entry: first}
  end

  defp after_watched(first, []), do: %ContinueTarget{action: :replay, entry: first}

  defp last_watched_index(entries) do
    entries
    |> Enum.with_index()
    |> Enum.filter(fn {entry, _} -> entry.last_watched_at end)
    |> Enum.max_by(
      fn {entry, index} -> {DateTime.to_unix(entry.last_watched_at, :microsecond), index} end,
      fn -> nil end
    )
    |> case do
      nil -> nil
      {_, index} -> index
    end
  end
end

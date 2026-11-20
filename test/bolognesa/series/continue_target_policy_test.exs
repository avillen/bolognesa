defmodule Bolognesa.Series.ContinueTargetPolicyTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Series.Domain.Policies.ContinueTargetPolicy
  alias Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus

  defp entry(id, opts \\ []) do
    %SeasonEntryStatus{
      season_id: Keyword.get(opts, :season, 1),
      season_number: Keyword.get(opts, :season, 1),
      number: id,
      episode_id: id,
      part_number: opts[:part],
      available?: Keyword.get(opts, :available?, true),
      last_watched_at: opts[:watched] && DateTime.from_unix!(opts[:watched])
    }
  end

  defp target(entries),
    do:
      with(
        %{action: action, entry: e} <- ContinueTargetPolicy.call(entries),
        do: {action, e.episode_id}
      )

  test "without entries there is no target" do
    assert ContinueTargetPolicy.call([]) == nil
  end

  test "specials are not part of the order" do
    assert ContinueTargetPolicy.call([entry(1, season: 0, watched: 10)]) == nil
    assert target([entry(1, season: 0, watched: 10), entry(2)]) == {:start, 2}
    assert target([entry(1, season: 0), entry(2, watched: 10), entry(3)]) == {:continue, 3}
  end

  test "starts at the first entry when nothing is watched" do
    assert target([entry(1), entry(2)]) == {:start, 1}
  end

  test "continues after the most recently watched entry, including a rewatch of an earlier one" do
    assert target([entry(1, watched: 10), entry(2, watched: 20), entry(3)]) == {:continue, 3}
    assert target([entry(1, watched: 30), entry(2, watched: 20), entry(3)]) == {:continue, 2}
  end

  test "ties after marking several entries go to the furthest entry" do
    assert target([entry(1, watched: 10), entry(2, watched: 10), entry(3, watched: 10), entry(4)]) ==
             {:continue, 4}

    assert target([entry(1, watched: 10), entry(2, watched: 10), entry(3), entry(4)]) ==
             {:continue, 3}
  end

  test "parts are separate entries in order" do
    entries = [entry(1, part: 1, watched: 10), entry(1, part: 2), entry(2)]
    assert ContinueTargetPolicy.call(entries).entry.part_number == 2
  end

  test "a known unavailable next entry is the target while an available entry follows" do
    assert target([entry(1, watched: 10), entry(2, available?: false), entry(3)]) ==
             {:continue, 2}
  end

  test "replays from the first entry when no available entry follows the watched one" do
    assert target([entry(1), entry(2, watched: 10)]) == {:replay, 1}
    assert target([entry(1), entry(2, watched: 10), entry(3, available?: false)]) == {:replay, 1}
  end
end

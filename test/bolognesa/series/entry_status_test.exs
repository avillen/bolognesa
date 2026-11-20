defmodule Bolognesa.Series.EntryStatusTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  # Episode 1 unsplit, episode 2 in two parts (the second unavailable), episode 3 unsplit.
  @entries for {episode, part, available?} <- [
                 {1, nil, true},
                 {2, 1, true},
                 {2, 2, false},
                 {3, nil, true}
               ],
               do: %EntryStatus{
                 season_id: 1,
                 season_number: 1,
                 number: episode,
                 episode_id: episode,
                 part_number: part,
                 available?: available?
               }

  defp adjacent(episode, part) do
    {previous, next} =
      EntryStatus.adjacent(@entries, %Entry{episode_id: episode, part_number: part})

    {key(previous), key(next)}
  end

  defp key(nil), do: nil
  defp key(entry), do: {entry.episode_id, entry.part_number}

  test "steps through listed entries, including unavailable parts" do
    assert adjacent(1, nil) == {nil, {2, 1}}
    assert adjacent(2, 1) == {{1, nil}, {2, 2}}
    assert adjacent(2, 2) == {{2, 1}, {3, nil}}
    assert adjacent(3, nil) == {{2, 2}, nil}
  end

  test "an unlisted entry of a split episode navigates around the whole episode" do
    assert adjacent(2, nil) == {{1, nil}, {3, nil}}
  end

  test "no entries have no neighbors" do
    assert EntryStatus.adjacent([], %Entry{episode_id: 1, part_number: nil}) ==
             {nil, nil}
  end
end

defmodule Bolognesa.Series.AutoAdvancePolicyTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Series.Domain.Policies.AutoAdvancePolicy
  alias Bolognesa.Series.Domain.ReadModels.SeasonEntryStatus
  alias Bolognesa.Series.Domain.ValueObjects.SeasonEntry

  defp entry(id, opts \\ []) do
    %SeasonEntryStatus{
      season_id: Keyword.get(opts, :season, 1),
      season_number: Keyword.get(opts, :season, 1),
      number: id,
      episode_id: id,
      part_number: opts[:part],
      available?: Keyword.get(opts, :available?, true)
    }
  end

  defp played(id, part \\ nil), do: [%SeasonEntry{episode_id: id, part_number: part}]

  defp next(entries, played) do
    with {:ok, e} <- AutoAdvancePolicy.call(entries, played), do: {e.episode_id, e.part_number}
  end

  test "continues to the next consecutive available part" do
    entries = [entry(1, part: 1), entry(1, part: 2), entry(2)]
    assert next(entries, played(1, 1)) == {1, 2}
  end

  test "stops when the next part is unavailable or not consecutive" do
    assert next([entry(1, part: 1), entry(1, part: 2, available?: false)], played(1, 1)) ==
             {:error, :part_unavailable}

    assert next([entry(1, part: 1), entry(1, part: 3)], played(1, 1)) ==
             {:error, :part_unavailable}
  end

  test "goes to the next episode after the last part or an unsplit entry" do
    assert next([entry(1, part: 1), entry(1, part: 2), entry(2)], played(1, 2)) == {2, nil}
    assert next([entry(1), entry(2)], played(1)) == {2, nil}
  end

  test "goes after the last episode of a file covering several" do
    entries = [entry(1), entry(2), entry(3)]
    assert next(entries, played(1) ++ played(2)) == {3, nil}
  end

  test "skips unavailable episodes, also across seasons" do
    entries = [entry(1), entry(2, available?: false), entry(3, season: 2)]
    assert next(entries, played(1)) == {3, nil}
  end

  test "the next episode must start at an unsplit or first available entry" do
    assert next([entry(1), entry(2, part: 2)], played(1)) == {:error, :part_unavailable}

    assert next([entry(1), entry(2, part: 1, available?: false), entry(2, part: 2)], played(1)) ==
             {:error, :part_unavailable}

    assert next([entry(1), entry(2, part: 1), entry(2, part: 2)], played(1)) == {2, 1}
  end

  test "specials are ordered before the regular seasons" do
    assert next([entry(1, season: 0), entry(2)], played(1)) == {2, nil}
    assert next([entry(1, season: 0), entry(2)], played(2)) == {:error, :not_found}
  end

  test "nothing follows or the played entry is unknown" do
    assert next([entry(1)], played(1)) == {:error, :not_found}
    assert next([entry(1), entry(2, available?: false)], played(1)) == {:error, :not_found}
    assert next([entry(1)], played(9)) == {:error, :not_found}
  end
end

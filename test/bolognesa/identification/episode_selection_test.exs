defmodule Bolognesa.Identification.EpisodeSelectionTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Identification.Domain.ValueObjects.Series.{
    EpisodeDetails,
    EpisodeSelection,
    SeasonDetails,
    SeriesDetails
  }

  test "validates a complete ordered selection including specials" do
    series = %SeriesDetails{provider_id: 201, title: "Serie"}

    season = %SeasonDetails{
      provider_id: 301,
      series_provider_id: 201,
      number: 0,
      episodes: [
        %EpisodeDetails{provider_id: 401, season_number: 0, number: 1, title: "Uno"},
        %EpisodeDetails{provider_id: 402, season_number: 0, number: 2, title: "Dos"}
      ]
    }

    assert {:ok, selection} = EpisodeSelection.new(series, season, [2, 1])
    assert Enum.map(selection.episodes, & &1.number) == [2, 1]
    assert {:error, :incomplete_episodes} = EpisodeSelection.new(series, season, [1, 99])

    for numbers <- [[], [0], [1, 1], Enum.to_list(1..101)] do
      assert {:error, :invalid_selection} = EpisodeSelection.new(series, season, numbers)
    end

    assert {:error, :invalid_response} =
             EpisodeSelection.new(series, %{season | series_provider_id: 999}, [1])

    assert {:error, :invalid_response} =
             EpisodeSelection.new(
               series,
               %{season | episodes: season.episodes ++ season.episodes},
               [1]
             )

    assert {:error, :invalid_response} = EpisodeSelection.new(%{series | title: ""}, season, [1])
  end
end

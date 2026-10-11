defmodule Bolognesa.Identification.EpisodeHintTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Identification.Domain.ValueObjects.Series.EpisodeHint

  test "recognizes both conventions specials repetitions and inclusive ranges" do
    for {name, season, numbers} <- [
          {"Serie.Ejemplo.S01E02.mkv", 1, [2]},
          {"Serie Ejemplo 1x02.mp4", 1, [2]},
          {"Serie Ejemplo S00E01.mkv", 0, [1]},
          {"Serie Ejemplo S01E01E02.mkv", 1, [1, 2]},
          {"Serie Ejemplo S01E01-E03.mkv", 1, [1, 2, 3]},
          {"Serie Ejemplo 1x01-03.mkv", 1, [1, 2, 3]},
          {"Serie Ejemplo 1x01x02.mkv", 1, [1, 2]},
          {"Serie.Ejemplo.s01e02.1080p.WEB-DL.mkv", 1, [2]}
        ] do
      assert {:ok, hint} = EpisodeHint.from_path(name)
      assert hint.title == "Serie Ejemplo"
      assert hint.season_number == season
      assert hint.episode_numbers == numbers
    end
  end

  test "uses relative series folders and validates season folders" do
    for folder <- ["Season 1", "Temporada 1", "S01"] do
      assert {:ok, %{title: "Serie Ejemplo", year: 2001, episode_numbers: [2]}} =
               EpisodeHint.from_path("Serie Ejemplo (2001)/#{folder}/S01E02.mkv")
    end

    assert {:ok, %{title: "Serie", season_number: 0}} =
             EpisodeHint.from_path("Serie/Especiales/S00E01.mkv")

    assert {:error, :ambiguous_name} = EpisodeHint.from_path("Serie/Season 2/S01E02.mkv")
    assert {:error, :unusable_name} = EpisodeHint.from_path("S01E02.mkv")
  end

  test "rejects ambiguous invalid and excessive selections without guesses" do
    for name <- ["Serie S01E00.mkv", "Serie S01E03-E01.mkv", "Serie S01E01E01.mkv"] do
      assert {:error, :invalid_episode_numbers} = EpisodeHint.from_path(name)
    end

    assert {:error, :too_many_episodes} = EpisodeHint.from_path("Serie 1x01-101.mkv")
    assert {:error, :ambiguous_name} = EpisodeHint.from_path("Serie S01E01 S02E02.mkv")

    for name <- [
          "Serie S01E01S02E02.mkv",
          "Serie 1x01S02E02.mkv",
          "Serie S01E01E.mkv",
          "Serie S01E01-E.mkv"
        ] do
      assert {:error, _} = EpisodeHint.from_path(name)
    end

    assert {:error, :unusable_name} = EpisodeHint.from_path("Serie 123.mkv")
    assert {:error, :unusable_name} = EpisodeHint.from_path(<<255>>)
    assert {:error, :unusable_name} = EpisodeHint.from_path("/private/Serie/S01E01.mkv")
  end
end

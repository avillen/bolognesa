defmodule Bolognesa.Identification.TitleHintTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Identification.Domain.TitleHint

  test "extracts title and year from a release name without directories" do
    assert {:ok, %{title: "Mi pelicula", year: 2001}} =
             TitleHint.from_path("privado/carpeta/Mi.pelicula.(2001).1080p.mkv")

    assert {:ok, %{title: "Otra película", year: nil}} =
             TitleHint.from_path("películas/Otra_película.mp4")
  end

  test "rejects invalid UTF-8 and names without a title" do
    assert {:error, :unusable_name} = TitleHint.from_path(<<"privado/pelicula-", 255, ".mkv">>)
    assert {:error, :unusable_name} = TitleHint.from_path("carpeta/1080p.BluRay.mkv")
    assert {:error, :unusable_name} = TitleHint.from_path("carpeta/.mp4")
  end
end

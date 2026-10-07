defmodule Bolognesa.Catalog.MovieTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Catalog.Domain.Movie

  test "requires a provider identity and usable title" do
    assert {:error, :invalid_movie} = Movie.new(%{provider: :tmdb, provider_id: 0, title: ""})

    assert {:ok, movie} =
             Movie.new(%{provider: :tmdb, provider_id: 42, title: "La película", year: 2001})

    assert movie.provider_id == 42
    assert movie.title == "La película"
  end
end

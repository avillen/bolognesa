defmodule Bolognesa.Identification.NewMovieTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Identification.Domain.ValueObjects.Movies.NewMovie

  test "requires a provider identity and usable title" do
    assert {:error, :invalid_movie} =
             NewMovie.new(%{provider: :tmdb, provider_id: 0, title: ""})

    assert {:error, :invalid_movie} =
             NewMovie.new(%{provider: :other, provider_id: 42, title: "La película"})

    assert {:ok, movie} =
             NewMovie.new(%{provider: :tmdb, provider_id: 42, title: " La película ", year: 2001})

    assert movie.__struct__ == NewMovie
    assert movie.provider_id == 42
    assert movie.title == "La película"
    assert movie.year == 2001
  end

  test "rejects optional metadata with the wrong type" do
    assert {:error, :invalid_movie} =
             NewMovie.new(%{provider: :tmdb, provider_id: 42, title: "La película", year: "2001"})

    assert {:error, :invalid_movie} =
             NewMovie.new(%{provider: :tmdb, provider_id: 42, title: "La película", overview: 42})
  end
end

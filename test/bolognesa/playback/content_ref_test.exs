defmodule Bolognesa.Playback.ContentRefTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Playback.Domain.ValueObjects.ContentRef

  test "video references require an explicit playable type and a positive integer" do
    assert ContentRef.valid?({:movie, 1})
    assert ContentRef.valid?({:episode, 1})

    for invalid <- [1, nil, {:series, 1}, {:track, 1}, {:movie, 0}, {:episode, -1}, {:movie, "1"}] do
      refute ContentRef.valid?(invalid)
    end
  end
end

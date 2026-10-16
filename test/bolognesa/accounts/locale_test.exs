defmodule Bolognesa.Accounts.LocaleTest do
  use ExUnit.Case, async: true
  alias Bolognesa.Accounts.Domain.ValueObjects.Locale

  test "accepts only explicit supported languages and automatic" do
    for value <- [nil, "es", "en"], do: assert(Locale.validate(value) == {:ok, value})

    for value <- ["en-US", "fr", "", %{}, ["en"]],
        do: assert(Locale.validate(value) == {:error, :invalid_locale})
  end
end

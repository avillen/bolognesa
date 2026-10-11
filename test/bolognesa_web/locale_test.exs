defmodule BolognesaWeb.LocaleTest do
  use ExUnit.Case, async: true
  alias BolognesaWeb.Locale

  test "negotiates regional variants, quality and stable order" do
    assert Locale.negotiate("en-US,en;q=0.9,es;q=0.5") == "en"
    assert Locale.negotiate("es;q=0.5,en;q=0.9") == "en"
    assert Locale.negotiate("en;q=0.5,es;q=0.5") == "en"
    assert Locale.negotiate("de,en;q=0.4") == "en"
    assert Locale.negotiate("EN-gb") == "en"
  end

  test "ignores invalid quality and unsupported input" do
    for header <- [nil, "", "fr", "en;q=nope", "en;q=2", "en;q=-1", "en_US", "en;q=0"] do
      assert Locale.negotiate(header) == "es"
    end
  end

  test "exclusions constrain wildcard and regional fallback" do
    assert Locale.negotiate("en;q=0,es;q=0.8") == "es"
    assert Locale.negotiate("es;q=0,*;q=0.8") == "en"
    assert Locale.negotiate("en;q=0,en-US;q=0.9,es") == "es"
    assert Locale.negotiate("en;q=oops,es") == "es"
  end
end

defmodule BolognesaWeb.Components.UI.HelpersTest do
  use ExUnit.Case, async: true

  import BolognesaWeb.Components.UI.Helpers

  test "extra classes replace conflicting variant utilities instead of losing to CSS order" do
    classes =
      %{variant: "ghost"}
      |> button_variant("whitespace-normal px-3 font-normal text-[13px]")
      |> String.split()

    assert "whitespace-normal" in classes
    assert "px-3" in classes
    assert "font-normal" in classes
    refute "whitespace-nowrap" in classes
    refute "px-4" in classes
    refute "font-semibold" in classes
    refute "text-sm" in classes
  end
end

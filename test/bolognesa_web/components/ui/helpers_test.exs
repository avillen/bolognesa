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

  test "nav carries its own geometry, active ring and focus offset" do
    classes = %{variant: "nav"} |> button_variant() |> String.split()

    for class <-
          ~w(justify-start gap-2.5 whitespace-normal px-3 text-[13px] font-normal aria-[current=page]:ring-1 focus-visible:outline-offset-2!) do
      assert class in classes
    end

    refute "whitespace-nowrap" in classes
    refute "px-4" in classes
    refute "font-semibold" in classes
    refute "text-sm" in classes
  end

  test "pill shape rounds any size" do
    classes = %{size: "lg", shape: "pill"} |> button_variant() |> String.split()

    assert "rounded-full" in classes
    refute "rounded-lg" in classes
  end

  test "every button size keeps a 44px target" do
    for size <- ~w(default sm lg icon round) do
      classes = %{size: size} |> button_variant() |> String.split()

      assert Enum.any?(classes, &(&1 in ~w(min-h-11 min-h-12 size-11))),
             "size #{size} is under 44px: #{inspect(classes)}"
    end
  end
end

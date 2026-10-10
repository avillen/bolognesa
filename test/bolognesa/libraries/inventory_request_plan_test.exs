defmodule Bolognesa.Libraries.InventoryRequestPlanTest do
  use ExUnit.Case, async: true

  alias Bolognesa.Libraries.Application.InventoryRequestPlan
  alias Bolognesa.Libraries.Domain.{MediaFile, NewMediaFile}

  @modified ~U[2026-10-03 00:00:00Z]
  @generation "current"

  test "new and changed files request both downstream jobs" do
    entry = entry(5)

    assert %{revision: 1, new_discovery?: true, inspect?: true, identify?: true} =
             InventoryRequestPlan.for_entry(nil, false, entry, false, @generation)

    assert %{revision: 2, new_discovery?: true, inspect?: true, identify?: true} =
             InventoryRequestPlan.for_entry(previous(), true, entry(6), false, @generation)
  end

  test "repeated observations do not request work or increase the discovery count" do
    prior = %{previous() | last_seen_generation: @generation}

    assert %{revision: 1, new_discovery?: false, inspect?: false, identify?: false} =
             InventoryRequestPlan.for_entry(prior, true, entry(5), false, @generation)

    assert %{revision: 1, new_discovery?: false, inspect?: false, identify?: false} =
             InventoryRequestPlan.for_entry(prior, true, entry(5), true, @generation)
  end

  test "an unchanged file without technical state requests only inspection" do
    assert %{revision: 1, new_discovery?: true, inspect?: true, identify?: false} =
             InventoryRequestPlan.for_entry(previous(), false, entry(5), false, @generation)
  end

  test "a forced scan requests inspection once without reidentifying an unchanged file" do
    assert %{revision: 1, new_discovery?: true, inspect?: true, identify?: false} =
             InventoryRequestPlan.for_entry(previous(), true, entry(5), true, @generation)
  end

  test "restoring a missing file requests both downstream jobs" do
    prior = %{previous() | availability: :missing}

    assert %{revision: 1, new_discovery?: true, inspect?: true, identify?: true} =
             InventoryRequestPlan.for_entry(prior, true, entry(5), false, @generation)
  end

  defp entry(size),
    do: %NewMediaFile{relative_path: "a.mp4", size_bytes: size, modified_at: @modified}

  defp previous do
    %MediaFile{
      id: 1,
      library_id: 1,
      relative_path: "a.mp4",
      size_bytes: 5,
      modified_at: @modified,
      availability: :available,
      revision: 1,
      last_seen_generation: "previous"
    }
  end
end

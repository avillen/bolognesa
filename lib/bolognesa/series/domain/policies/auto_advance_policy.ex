defmodule Bolognesa.Series.Domain.Policies.AutoAdvancePolicy do
  @moduledoc """
  Chooses the entry to open after the played entries end, from the series entries in order.

  Continue to the next consecutive part of the last played entry when it is available.
  After the last part, or an unsplit entry, open the first entry of the next episode with an
  available entry; it must be unsplit or part 1 and available. Specials (season 0) are
  ordered like any other season.
  """
  alias Bolognesa.Series.Domain.ReadModels.EntryStatus
  alias Bolognesa.Series.Domain.ValueObjects.Entry

  @spec call([EntryStatus.t()], [Entry.t()]) ::
          {:ok, EntryStatus.t()} | {:error, :not_found | :part_unavailable}
  def call(entries, played) do
    case entries
         |> Enum.reverse()
         |> Enum.split_while(&(EntryStatus.entry(&1) not in played)) do
      {following, [last | _]} -> advance(last, Enum.reverse(following))
      {_, []} -> {:error, :not_found}
    end
  end

  defp advance(%{part_number: part, episode_id: id}, [%{episode_id: id} = next | _])
       when part != nil do
    if next.part_number == part + 1 and next.available?,
      do: {:ok, next},
      else: {:error, :part_unavailable}
  end

  defp advance(_last, following) do
    case Enum.find(following, & &1.available?) do
      nil -> {:error, :not_found}
      %{episode_id: id} -> following |> Enum.find(&(&1.episode_id == id)) |> first_entry()
    end
  end

  defp first_entry(%{available?: true, part_number: part} = entry) when part in [nil, 1],
    do: {:ok, entry}

  defp first_entry(_entry), do: {:error, :part_unavailable}
end

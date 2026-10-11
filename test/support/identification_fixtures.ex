defmodule Bolognesa.IdentificationFixtures do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Bolognesa.Repo

  @spec insert_decision!(map(), [pos_integer()]) :: IdentificationSchema.t()
  def insert_decision!(attrs, ids) do
    row = Repo.insert!(IdentificationSchema.changeset(%IdentificationSchema{}, attrs))

    Enum.with_index(ids, 1)
    |> Enum.each(fn {id, position} ->
      Repo.insert!(%IdentificationEntrySchema{
        identification_id: row.id,
        catalog_entry_id: id,
        position: position
      })
    end)

    row
  end
end

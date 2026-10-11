defmodule Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "identification_entries" do
    field :identification_id, :id
    field :catalog_entry_id, :id
    field :position, :integer
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> validate_required([:identification_id, :catalog_entry_id, :position])
    |> validate_number(:position, greater_than: 0)
    |> foreign_key_constraint(:identification_id)
    |> foreign_key_constraint(:catalog_entry_id)
    |> unique_constraint([:identification_id, :catalog_entry_id])
    |> unique_constraint([:identification_id, :position])
    |> check_constraint(:position, name: :identification_entries_position_positive)
  end
end

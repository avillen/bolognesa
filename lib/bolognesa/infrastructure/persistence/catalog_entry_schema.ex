defmodule Bolognesa.Infrastructure.Persistence.CatalogEntrySchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "catalog_entries" do
    field :kind, Ecto.Enum, values: [:movie, :series, :season, :episode]
    field :provider, Ecto.Enum, values: [:tmdb]
    field :resource_type, Ecto.Enum, values: [:movie, :series, :season, :episode]
    field :provider_id, :integer
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:kind, :provider, :resource_type, :provider_id])
    |> validate_required([:kind, :provider, :resource_type, :provider_id])
    |> validate_number(:provider_id, greater_than: 0)
    |> unique_constraint(:provider_id,
      name: :catalog_entries_provider_resource_type_provider_id_index
    )
    |> check_constraint(:provider_id, name: :catalog_entries_provider_id_positive)
    |> check_constraint(:kind, name: :catalog_entries_kind_valid)
    |> check_constraint(:provider, name: :catalog_entries_provider_valid)
    |> check_constraint(:resource_type, name: :catalog_entries_resource_type_valid)
  end
end

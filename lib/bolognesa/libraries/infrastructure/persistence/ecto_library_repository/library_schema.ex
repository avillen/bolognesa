defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "libraries" do
    field :name, :string
    field :path, :string
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(library, attrs) do
    library
    |> cast(attrs, [:name, :path])
    |> validate_required([:name, :path])
    |> unique_constraint(:path)
  end
end

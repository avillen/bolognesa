defmodule Bolognesa.Infrastructure.Persistence.LibrarySchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          path: String.t() | nil,
          content_type: :movie | :series | nil
        }

  schema "libraries" do
    field :name, :string
    field :path, :string
    field :content_type, Ecto.Enum, values: [:movie, :series], default: :movie
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(library, attrs) do
    library
    |> cast(attrs, [:name, :path, :content_type])
    |> validate_required([:name, :path, :content_type])
    |> unique_constraint(:path)
    |> check_constraint(:content_type, name: :libraries_content_type_valid)
  end
end

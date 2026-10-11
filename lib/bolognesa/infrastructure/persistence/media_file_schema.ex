defmodule Bolognesa.Infrastructure.Persistence.MediaFileSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          library_id: integer() | nil,
          relative_path: binary() | nil,
          size_bytes: non_neg_integer() | nil,
          modified_at: DateTime.t() | nil,
          availability: :available | :missing,
          revision: pos_integer(),
          last_seen_generation: Ecto.UUID.t() | nil
        }

  schema "media_files" do
    field :library_id, :id
    field :relative_path, :binary
    field :size_bytes, :integer
    field :modified_at, :utc_datetime_usec
    field :availability, Ecto.Enum, values: [:available, :missing], default: :available
    field :revision, :integer, default: 1
    field :last_seen_generation, Ecto.UUID
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(file, attrs) do
    file
    |> change(attrs)
    |> validate_required([
      :library_id,
      :relative_path,
      :size_bytes,
      :modified_at,
      :availability,
      :revision,
      :last_seen_generation
    ])
    |> validate_number(:size_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:revision, greater_than: 0)
    |> foreign_key_constraint(:library_id)
    |> unique_constraint([:library_id, :relative_path])
    |> check_constraint(:size_bytes, name: :media_files_size_nonnegative)
    |> check_constraint(:revision, name: :media_files_revision_positive)
  end
end

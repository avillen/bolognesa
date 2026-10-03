defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

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

defmodule Bolognesa.Infrastructure.Persistence.MusicImportSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "music_imports" do
    field :media_file_id, :id
    field :observed_revision, :integer
    field :inspection_token, Ecto.UUID
    field :state, Ecto.Enum, values: [:pending, :running, :succeeded, :failed]
    field :job_id, :integer

    field :failure_reason, Ecto.Enum,
      values: [:storage_unavailable, :attempts_exhausted, :unexpected_failure]

    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> change(attrs)
    |> unique_constraint(:media_file_id)
    |> check_constraint(:observed_revision, name: :music_imports_revision_positive)
  end
end

defmodule Bolognesa.Infrastructure.Persistence.InspectionSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "media_inspections" do
    field :media_file_id, :id
    field :token, Ecto.UUID
    field :observed_revision, :integer
    field :state, Ecto.Enum, values: [:pending, :running, :succeeded, :failed], default: :pending

    field :failure_reason, Ecto.Enum,
      values: [
        :source_changed,
        :source_inaccessible,
        :unsafe_entry,
        :unreadable,
        :unsupported,
        :timeout,
        :tool_unavailable,
        :invalid_output,
        :storage_unavailable,
        :attempts_exhausted,
        :unexpected_failure
      ]

    field :job_id, :integer
    field :format, :string
    field :duration_ms, :integer
    field :music_tags, :map
    field :tracks, :map, default: %{"items" => []}
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(inspection, attrs) do
    inspection
    |> change(attrs)
    |> validate_required([:media_file_id, :token, :observed_revision, :state])
    |> validate_number(:observed_revision, greater_than: 0)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:media_file_id)
    |> unique_constraint(:media_file_id)
    |> check_constraint(:observed_revision, name: :media_inspections_revision_positive)
    |> check_constraint(:duration_ms, name: :media_inspections_duration_nonnegative)
    |> check_constraint(:state, name: :media_inspections_state_valid)
  end
end

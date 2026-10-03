defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.ScanSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "library_scans" do
    field :library_id, :id
    field :job_id, :integer

    field :state, Ecto.Enum,
      values: [:queued, :running, :retrying, :completed, :failed],
      default: :queued

    field :generation, Ecto.UUID
    field :attempt, :integer, default: 0
    field :files_discovered, :integer, default: 0

    field :failure_reason, Ecto.Enum,
      values: [
        :source_inaccessible,
        :source_outside_roots,
        :source_changed,
        :entry_unreadable,
        :unsafe_entry,
        :storage_unavailable,
        :timeout,
        :attempts_exhausted,
        :unexpected_failure
      ]

    field :requested_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :attempt_started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, inserted_at: false)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(scan, attrs) do
    scan
    |> change(attrs)
    |> validate_required([:library_id, :state, :attempt, :files_discovered, :requested_at])
    |> validate_number(:attempt, greater_than_or_equal_to: 0)
    |> validate_number(:files_discovered, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:library_id)
    |> unique_constraint(:library_id, name: :library_scans_one_active)
    |> check_constraint(:attempt, name: :library_scans_attempt_nonnegative)
    |> check_constraint(:files_discovered, name: :library_scans_discovered_nonnegative)
  end
end

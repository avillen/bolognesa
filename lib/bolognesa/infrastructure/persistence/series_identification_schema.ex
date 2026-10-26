defmodule Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @states [:pending, :automatic, :manual, :manual_unidentified, :failed, :unmatched]

  schema "series_identifications" do
    field :media_file_id, :id
    field :part_number, :integer
    field :state, Ecto.Enum, values: @states, default: :pending
    field :origin, Ecto.Enum, values: [:automatic, :manual]
    field :observed_revision, :integer
    field :token, Ecto.UUID
    field :needs_review, :boolean, default: false
    field :failure_reason, :string
    field :candidate_data, :map, default: %{items: []}
    field :job_id, :integer
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(identification, attrs) do
    identification
    |> change(attrs)
    |> validate_required([:media_file_id, :state, :observed_revision, :token])
    |> validate_number(:part_number, greater_than: 0, less_than_or_equal_to: 100)
    |> check_constraint(:part_number, name: :series_identifications_part_valid)
    |> validate_number(:observed_revision, greater_than: 0)
    |> foreign_key_constraint(:media_file_id)
    |> unique_constraint(:media_file_id)
    |> check_constraint(:state, name: :series_identifications_state_valid)
    |> check_constraint(:observed_revision, name: :series_identifications_revision_positive)
  end
end

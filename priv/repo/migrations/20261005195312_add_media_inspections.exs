defmodule Bolognesa.Repo.Migrations.AddMediaInspections do
  use Ecto.Migration

  def change do
    alter table(:library_scans) do
      add :force_inspection, :boolean, null: false, default: false
    end

    create table(:media_inspections) do
      add :media_file_id, references(:media_files, on_delete: :delete_all), null: false
      add :token, :uuid, null: false
      add :observed_revision, :integer, null: false
      add :state, :string, null: false, default: "pending"
      add :failure_reason, :string
      add :job_id, :bigint
      add :format, :string
      add :duration_ms, :bigint
      add :tracks, :map, null: false, default: %{items: []}
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_inspections, [:media_file_id])

    create constraint(:media_inspections, :media_inspections_revision_positive,
             check: "observed_revision > 0"
           )

    create constraint(:media_inspections, :media_inspections_duration_nonnegative,
             check: "duration_ms IS NULL OR duration_ms >= 0"
           )

    create constraint(:media_inspections, :media_inspections_state_valid,
             check: "state IN ('pending', 'running', 'succeeded', 'failed')"
           )

    create table(:media_inspection_events) do
      add :media_file_id, references(:media_files, on_delete: :delete_all), null: false
      add :token, :uuid, null: false
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_inspection_events, [:media_file_id, :token])
    create index(:media_inspection_events, [:delivered_at, :id])
  end
end

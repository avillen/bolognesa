defmodule Bolognesa.Repo.Migrations.CreateLibraryScansAndMediaFiles do
  use Ecto.Migration

  def change do
    create table(:library_scans) do
      add :library_id, references(:libraries), null: false
      add :job_id, :bigint
      add :state, :string, null: false, default: "queued"
      add :generation, :uuid
      add :attempt, :integer, null: false, default: 0
      add :files_discovered, :bigint, null: false, default: 0
      add :failure_reason, :string
      add :requested_at, :utc_datetime_usec, null: false
      add :started_at, :utc_datetime_usec
      add :attempt_started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, inserted_at: false)
    end

    create unique_index(:library_scans, [:library_id],
             name: :library_scans_one_active,
             where: "state IN ('queued', 'running', 'retrying')"
           )

    create index(:library_scans, [:library_id, :requested_at, :id])
    create constraint(:library_scans, :library_scans_attempt_nonnegative, check: "attempt >= 0")

    create constraint(:library_scans, :library_scans_discovered_nonnegative,
             check: "files_discovered >= 0"
           )

    create table(:media_files) do
      add :library_id, references(:libraries), null: false
      add :relative_path, :binary, null: false
      add :size_bytes, :bigint, null: false
      add :modified_at, :utc_datetime_usec, null: false
      add :availability, :string, null: false, default: "available"
      add :revision, :integer, null: false, default: 1
      add :last_seen_generation, :uuid, null: false
    end

    create unique_index(:media_files, [:library_id, :relative_path])
    create index(:media_files, [:library_id, :last_seen_generation])
    create constraint(:media_files, :media_files_size_nonnegative, check: "size_bytes >= 0")
    create constraint(:media_files, :media_files_revision_positive, check: "revision > 0")
  end
end

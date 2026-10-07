defmodule Bolognesa.Repo.Migrations.CreateCatalogAndIdentifications do
  use Ecto.Migration

  def change do
    create table(:movies) do
      add :provider, :string, null: false
      add :provider_id, :integer, null: false
      add :title, :string, null: false
      add :original_title, :string
      add :year, :integer
      add :overview, :text
      add :poster_path, :string
      add :backdrop_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:movies, [:provider, :provider_id])
    create constraint(:movies, :movies_provider_id_positive, check: "provider_id > 0")
    create constraint(:movies, :movies_title_nonempty, check: "length(btrim(title)) > 0")

    create table(:media_identifications) do
      add :media_file_id, references(:media_files, on_delete: :delete_all), null: false
      add :movie_id, references(:movies, on_delete: :restrict)
      add :state, :string, null: false, default: "pending"
      add :origin, :string
      add :observed_revision, :integer, null: false
      add :token, :uuid, null: false
      add :needs_review, :boolean, null: false, default: false
      add :failure_reason, :string
      add :candidate_data, :map, null: false, default: %{items: []}
      add :job_id, :bigint
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_identifications, [:media_file_id])
    create index(:media_identifications, [:movie_id])

    create constraint(:media_identifications, :media_identifications_revision_positive,
             check: "observed_revision > 0"
           )

    create constraint(:media_identifications, :media_identifications_state_valid,
             check:
               "state IN ('pending', 'automatic', 'manual', 'manual_unidentified', 'failed', 'unmatched')"
           )

    create constraint(:media_identifications, :media_identifications_choice_valid,
             check:
               "(state IN ('automatic', 'manual') AND movie_id IS NOT NULL) OR " <>
                 "(state IN ('manual_unidentified', 'unmatched') AND movie_id IS NULL) OR " <>
                 "state IN ('pending', 'failed')"
           )

    create table(:media_identification_events) do
      add :media_file_id, references(:media_files, on_delete: :delete_all), null: false
      add :token, :uuid, null: false
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:media_identification_events, [:media_file_id, :token])
    create index(:media_identification_events, [:delivered_at, :id])
  end
end

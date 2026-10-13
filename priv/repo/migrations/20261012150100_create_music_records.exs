defmodule Bolognesa.Repo.Migrations.CreateMusicRecords do
  use Ecto.Migration

  def up do
    create table(:music_artists) do
      add :library_id, references(:libraries, on_delete: :restrict), null: false
      add :name, :text, null: false
      add :normalized_name, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:music_artists, [:library_id, :normalized_name])

    create table(:music_albums) do
      add :library_id, references(:libraries, on_delete: :restrict), null: false
      add :source_parent, :binary, null: false
      add :title, :text, null: false
      add :normalized_title, :text, null: false
      add :artist_id, references(:music_artists, on_delete: :restrict)
      add :album_artist_key, :text, null: false, default: ""
      add :year, :integer
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :music_albums,
             [:library_id, :source_parent, :normalized_title, :album_artist_key],
             name: :music_albums_grouping_index
           )

    create table(:music_tracks) do
      add :media_file_id, references(:media_files, on_delete: :restrict), null: false
      add :library_id, references(:libraries, on_delete: :restrict), null: false
      add :title, :text, null: false
      add :artist_id, references(:music_artists, on_delete: :restrict)
      add :album_id, references(:music_albums, on_delete: :restrict)
      add :disc_number, :integer
      add :track_number, :integer
      add :year, :integer
      add :observed_revision, :integer, null: false
      add :inspection_token, :uuid, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:music_tracks, [:media_file_id])

    create constraint(:music_tracks, :music_tracks_revision_positive,
             check: "observed_revision > 0"
           )

    create constraint(:music_tracks, :music_tracks_number_valid,
             check: "track_number BETWEEN 1 AND 9999"
           )

    create constraint(:music_tracks, :music_tracks_disc_valid,
             check: "disc_number BETWEEN 1 AND 9999"
           )

    create table(:music_imports) do
      add :media_file_id, references(:media_files, on_delete: :restrict), null: false
      add :observed_revision, :integer, null: false
      add :inspection_token, :uuid, null: false
      add :state, :text, null: false
      add :job_id, :bigint
      add :failure_reason, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:music_imports, [:media_file_id])

    create constraint(:music_imports, :music_imports_revision_positive,
             check: "observed_revision > 0"
           )

    create constraint(:music_imports, :music_imports_state_valid,
             check: "state IN ('pending','running','succeeded','failed')"
           )

    create constraint(:music_imports, :music_imports_reason_valid,
             check:
               "failure_reason IN ('storage_unavailable','attempts_exhausted','unexpected_failure')"
           )
  end

  def down do
    execute "DO $$ BEGIN IF EXISTS (SELECT 1 FROM libraries WHERE content_type = 'music') THEN RAISE EXCEPTION 'Remove music libraries explicitly before rollback'; END IF; END $$"
    drop table(:music_imports)
    drop table(:music_tracks)
    drop table(:music_albums)
    drop table(:music_artists)
  end
end

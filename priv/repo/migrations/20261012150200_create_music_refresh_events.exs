defmodule Bolognesa.Repo.Migrations.CreateMusicRefreshEvents do
  use Ecto.Migration

  def up do
    create table(:music_refresh_events) do
      add :media_file_id, references(:media_files, on_delete: :delete_all), null: false
      add :revision, :integer, null: false
      add :inspection_token, :uuid, null: false
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:music_refresh_events, [:media_file_id, :inspection_token])
    create index(:music_refresh_events, [:id], where: "delivered_at IS NULL")
  end

  def down do
    execute "DO $$ BEGIN IF EXISTS (SELECT 1 FROM libraries WHERE content_type = 'music') THEN RAISE EXCEPTION 'Remove music libraries explicitly before rollback'; END IF; END $$"
    drop table(:music_refresh_events)
  end
end

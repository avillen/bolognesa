defmodule Bolognesa.Repo.Migrations.CreateMusicRefreshEvents do
  use Ecto.Migration

  def change do
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
end

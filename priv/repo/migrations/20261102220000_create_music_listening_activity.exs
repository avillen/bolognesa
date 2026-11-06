defmodule Bolognesa.Repo.Migrations.CreateMusicListeningActivity do
  use Ecto.Migration

  def up do
    create table(:music_listening_activity, primary_key: false) do
      add :user_id, references(:accounts_users, on_delete: :delete_all), null: false
      add :track_id, references(:music_tracks, on_delete: :delete_all), null: false
      add :last_played_at, :utc_datetime_usec, null: false
    end

    create unique_index(:music_listening_activity, [:user_id, :track_id])
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM music_listening_activity) THEN
        RAISE EXCEPTION 'Cannot discard listening activity';
      END IF;
    END $$
    """

    drop table(:music_listening_activity)
  end
end

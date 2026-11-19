defmodule Bolognesa.Repo.Migrations.CreateSeriesWatchedEntries do
  use Ecto.Migration

  def up do
    create table(:series_watched_entries, primary_key: false) do
      add :user_id, references(:accounts_users, on_delete: :delete_all), null: false
      add :episode_id, references(:episodes, on_delete: :delete_all), null: false
      add :part_number, :integer
      add :last_watched_at, :utc_datetime_usec, null: false
    end

    execute """
    CREATE UNIQUE INDEX series_watched_entries_identity
    ON series_watched_entries (user_id, episode_id, part_number) NULLS NOT DISTINCT
    """

    create constraint(:series_watched_entries, :series_watched_entries_part_valid,
             check: "part_number IS NULL OR part_number BETWEEN 1 AND 100"
           )

    create index(:series_watched_entries, [:episode_id])
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM series_watched_entries) THEN
        RAISE EXCEPTION 'Cannot discard watched entries';
      END IF;
    END $$
    """

    drop table(:series_watched_entries)
  end
end

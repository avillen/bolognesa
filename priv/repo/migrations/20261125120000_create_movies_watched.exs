defmodule Bolognesa.Repo.Migrations.CreateMoviesWatched do
  use Ecto.Migration

  def up do
    create table(:movies_watched, primary_key: false) do
      add :user_id, references(:accounts_users, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :movie_id, references(:movies, on_delete: :delete_all), null: false, primary_key: true
      add :last_watched_at, :utc_datetime_usec, null: false
    end

    create index(:movies_watched, [:movie_id])
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM movies_watched) THEN
        RAISE EXCEPTION 'Cannot discard watched movies';
      END IF;
    END $$
    """

    drop table(:movies_watched)
  end
end

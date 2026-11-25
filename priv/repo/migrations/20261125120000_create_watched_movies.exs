defmodule Bolognesa.Repo.Migrations.CreateWatchedMovies do
  use Ecto.Migration

  def up do
    create table(:watched_movies, primary_key: false) do
      add :user_id, references(:accounts_users, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :movie_id, references(:movies, on_delete: :delete_all), null: false, primary_key: true
      add :last_watched_at, :utc_datetime_usec, null: false
    end

    create index(:watched_movies, [:movie_id])
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM watched_movies) THEN
        RAISE EXCEPTION 'Cannot discard watched movies';
      END IF;
    END $$
    """

    drop table(:watched_movies)
  end
end

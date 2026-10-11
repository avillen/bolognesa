defmodule Bolognesa.Repo.Migrations.RemoveMovieProviderColumns do
  use Ecto.Migration

  def up do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM movies m LEFT JOIN catalog_entries e ON e.id = m.id
                 WHERE e.id IS NULL OR m.provider IS DISTINCT FROM e.provider
                   OR m.provider_id IS DISTINCT FROM e.provider_id OR e.kind <> 'movie') THEN
        RAISE EXCEPTION 'movie identity mismatch';
      END IF;
    END $$
    """

    drop index(:movies, [:provider, :provider_id])
    drop constraint(:movies, :movies_provider_id_positive)

    alter table(:movies) do
      remove :provider
      remove :provider_id
    end
  end

  def down do
    alter table(:movies) do
      add :provider, :string
      add :provider_id, :integer
    end

    flush()

    execute "UPDATE movies m SET provider = e.provider, provider_id = e.provider_id FROM catalog_entries e WHERE e.id = m.id"

    execute "ALTER TABLE movies ALTER COLUMN provider SET NOT NULL, ALTER COLUMN provider_id SET NOT NULL"

    create unique_index(:movies, [:provider, :provider_id])
    create constraint(:movies, :movies_provider_id_positive, check: "provider_id > 0")
  end
end

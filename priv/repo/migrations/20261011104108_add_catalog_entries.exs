defmodule Bolognesa.Repo.Migrations.AddCatalogEntries do
  use Ecto.Migration

  def up do
    create table(:catalog_entries) do
      add :kind, :string, null: false
      add :provider, :string, null: false
      add :resource_type, :string, null: false
      add :provider_id, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:catalog_entries, [:provider, :resource_type, :provider_id])
    create constraint(:catalog_entries, :catalog_entries_kind_valid, check: "kind = 'movie'")

    create constraint(:catalog_entries, :catalog_entries_provider_valid,
             check: "provider = 'tmdb'"
           )

    create constraint(:catalog_entries, :catalog_entries_resource_type_valid,
             check: "resource_type = 'movie'"
           )

    create constraint(:catalog_entries, :catalog_entries_provider_id_positive,
             check: "provider_id > 0"
           )

    execute """
    INSERT INTO catalog_entries (id, kind, provider, resource_type, provider_id, inserted_at, updated_at)
    SELECT id, 'movie', provider, 'movie', provider_id, inserted_at, updated_at FROM movies
    """

    execute "SELECT setval(pg_get_serial_sequence('catalog_entries', 'id'), COALESCE(MAX(id), 1), MAX(id) IS NOT NULL) FROM catalog_entries"

    execute "ALTER TABLE movies ALTER COLUMN id DROP DEFAULT"

    execute "ALTER TABLE movies ADD CONSTRAINT movies_id_fkey FOREIGN KEY (id) REFERENCES catalog_entries(id) ON DELETE RESTRICT"
  end

  def down do
    execute "ALTER TABLE movies DROP CONSTRAINT movies_id_fkey"
    execute "ALTER TABLE movies ALTER COLUMN id SET DEFAULT nextval('movies_id_seq'::regclass)"

    execute "SELECT setval('movies_id_seq', COALESCE(MAX(id), 1), MAX(id) IS NOT NULL) FROM movies"

    drop table(:catalog_entries)
  end
end

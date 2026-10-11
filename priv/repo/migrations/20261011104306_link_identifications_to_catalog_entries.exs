defmodule Bolognesa.Repo.Migrations.LinkIdentificationsToCatalogEntries do
  use Ecto.Migration

  def up do
    drop constraint(:media_identifications, :media_identifications_choice_valid)
    drop constraint(:media_identifications, :media_identifications_movie_id_fkey)
    drop index(:media_identifications, [:movie_id])
    rename table(:media_identifications), :movie_id, to: :catalog_entry_id

    execute "ALTER TABLE media_identifications ADD CONSTRAINT media_identifications_catalog_entry_id_fkey FOREIGN KEY (catalog_entry_id) REFERENCES catalog_entries(id) ON DELETE RESTRICT"

    create index(:media_identifications, [:catalog_entry_id])

    create constraint(:media_identifications, :media_identifications_choice_valid,
             check: choice_check("catalog_entry_id")
           )
  end

  def down do
    drop constraint(:media_identifications, :media_identifications_choice_valid)
    drop constraint(:media_identifications, :media_identifications_catalog_entry_id_fkey)
    drop index(:media_identifications, [:catalog_entry_id])
    rename table(:media_identifications), :catalog_entry_id, to: :movie_id

    execute "ALTER TABLE media_identifications ADD CONSTRAINT media_identifications_movie_id_fkey FOREIGN KEY (movie_id) REFERENCES movies(id) ON DELETE RESTRICT"

    create index(:media_identifications, [:movie_id])

    create constraint(:media_identifications, :media_identifications_choice_valid,
             check: choice_check("movie_id")
           )
  end

  defp choice_check(column) do
    "(state IN ('automatic', 'manual') AND #{column} IS NOT NULL) OR " <>
      "(state IN ('manual_unidentified', 'unmatched') AND #{column} IS NULL) OR " <>
      "state IN ('pending', 'failed')"
  end
end

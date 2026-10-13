defmodule Bolognesa.Repo.Migrations.AddMusicLibraryInspection do
  use Ecto.Migration

  def up do
    drop constraint(:libraries, :libraries_content_type_valid)

    create constraint(:libraries, :libraries_content_type_valid,
             check: "content_type IN ('movie', 'series', 'music')"
           )

    alter table(:media_inspections), do: add(:music_tags, :map)
  end

  def down do
    execute "DO $$ BEGIN IF EXISTS (SELECT 1 FROM libraries WHERE content_type = 'music') THEN RAISE EXCEPTION 'Remove music libraries explicitly before rollback'; END IF; END $$"
    alter table(:media_inspections), do: remove(:music_tags)
    drop constraint(:libraries, :libraries_content_type_valid)

    create constraint(:libraries, :libraries_content_type_valid,
             check: "content_type IN ('movie', 'series')"
           )
  end
end

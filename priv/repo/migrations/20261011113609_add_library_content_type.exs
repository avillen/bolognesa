defmodule Bolognesa.Repo.Migrations.AddLibraryContentType do
  use Ecto.Migration

  def up do
    alter table(:libraries) do
      add :content_type, :string, null: false, default: "movie"
    end

    create constraint(:libraries, :libraries_content_type_valid,
             check: "content_type IN ('movie', 'series')"
           )
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM libraries WHERE content_type = 'series') THEN
        RAISE EXCEPTION 'cannot remove library type while series libraries exist';
      END IF;
    END $$;
    """

    drop constraint(:libraries, :libraries_content_type_valid)
    alter table(:libraries), do: remove(:content_type)
  end
end

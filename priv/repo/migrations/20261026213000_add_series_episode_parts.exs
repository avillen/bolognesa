defmodule Bolognesa.Repo.Migrations.AddSeriesEpisodeParts do
  use Ecto.Migration

  def up do
    alter table(:series_identifications) do
      add :part_number, :integer
    end

    create constraint(:series_identifications, :series_identifications_part_valid,
             check:
               "part_number IS NULL OR (part_number BETWEEN 1 AND 100 AND state IN ('automatic', 'manual'))"
           )
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM series_identifications WHERE part_number IS NOT NULL) THEN
        RAISE EXCEPTION 'cannot remove episode parts while numbered parts exist';
      END IF;
    END $$;
    """

    drop constraint(:series_identifications, :series_identifications_part_valid)

    alter table(:series_identifications) do
      remove :part_number
    end
  end
end

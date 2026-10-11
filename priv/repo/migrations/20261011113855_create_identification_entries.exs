defmodule Bolognesa.Repo.Migrations.CreateIdentificationEntries do
  use Ecto.Migration

  def up do
    create table(:identification_entries) do
      add :identification_id, references(:media_identifications, on_delete: :delete_all),
        null: false

      add :catalog_entry_id, references(:catalog_entries, on_delete: :restrict), null: false
      add :position, :integer, null: false
    end

    create unique_index(:identification_entries, [:identification_id, :catalog_entry_id])
    create unique_index(:identification_entries, [:identification_id, :position])
    create index(:identification_entries, [:catalog_entry_id])

    create constraint(:identification_entries, :identification_entries_position_positive,
             check: "position > 0"
           )

    execute """
    INSERT INTO identification_entries (identification_id, catalog_entry_id, position)
    SELECT id, catalog_entry_id, 1 FROM media_identifications
    WHERE catalog_entry_id IS NOT NULL AND state IN ('automatic', 'manual')
    """

    # Pending/failed rows sometimes retained an obsolete association in the old model.
    # Those were never authorized for playback; only confirmed decisions migrate.
    execute """
    DO $$ BEGIN
      IF (SELECT count(*) FROM media_identifications WHERE catalog_entry_id IS NOT NULL AND state IN ('automatic','manual'))
        <> (SELECT count(*) FROM identification_entries) THEN
        RAISE EXCEPTION 'identification association backfill mismatch';
      END IF;
    END $$;
    """

    drop constraint(:media_identifications, :media_identifications_choice_valid)
    drop index(:media_identifications, [:catalog_entry_id])
    alter table(:media_identifications), do: remove(:catalog_entry_id)

    execute """
    CREATE FUNCTION validate_identification_entry() RETURNS trigger AS $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM media_identifications WHERE id = NEW.identification_id AND state IN ('automatic','manual')) THEN
        RAISE EXCEPTION 'association requires a confirmed decision' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER identification_entries_confirmed
    BEFORE INSERT OR UPDATE ON identification_entries
    FOR EACH ROW EXECUTE FUNCTION validate_identification_entry();
    """
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM libraries WHERE content_type = 'series')
        OR EXISTS (SELECT 1 FROM catalog_entries WHERE kind <> 'movie')
        OR EXISTS (SELECT 1 FROM identification_entries GROUP BY identification_id HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'cannot restore singular movie associations while series or multiple associations exist';
      END IF;
    END $$;
    """

    alter table(:media_identifications) do
      add :catalog_entry_id, references(:catalog_entries, on_delete: :restrict)
    end

    execute """
    UPDATE media_identifications AS decision SET catalog_entry_id = relation.catalog_entry_id
    FROM identification_entries AS relation WHERE relation.identification_id = decision.id
    """

    create index(:media_identifications, [:catalog_entry_id])

    create constraint(:media_identifications, :media_identifications_choice_valid,
             check:
               "(state IN ('automatic','manual') AND catalog_entry_id IS NOT NULL) OR (state IN ('manual_unidentified','unmatched') AND catalog_entry_id IS NULL) OR state IN ('pending','failed')"
           )

    execute "DROP TRIGGER identification_entries_confirmed ON identification_entries"
    execute "DROP FUNCTION validate_identification_entry()"
    drop table(:identification_entries)
  end
end

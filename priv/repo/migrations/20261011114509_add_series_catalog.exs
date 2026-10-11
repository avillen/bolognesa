defmodule Bolognesa.Repo.Migrations.AddSeriesCatalog do
  use Ecto.Migration

  def up do
    drop constraint(:catalog_entries, :catalog_entries_kind_valid)
    drop constraint(:catalog_entries, :catalog_entries_resource_type_valid)

    create constraint(:catalog_entries, :catalog_entries_kind_valid,
             check: "kind IN ('movie','series','season','episode')"
           )

    create constraint(:catalog_entries, :catalog_entries_resource_type_valid,
             check: "resource_type = kind"
           )

    create table(:series, primary_key: false) do
      add :id, references(:catalog_entries, on_delete: :restrict), primary_key: true
      add :title, :string, null: false
      add :year, :integer
      add :overview, :text
      add :poster_path, :string
      add :backdrop_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:seasons, primary_key: false) do
      add :id, references(:catalog_entries, on_delete: :restrict), primary_key: true
      add :series_id, references(:series, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :title, :string
      add :poster_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:seasons, [:series_id, :number])
    create constraint(:seasons, :seasons_number_valid, check: "number >= 0")

    create table(:episodes, primary_key: false) do
      add :id, references(:catalog_entries, on_delete: :restrict), primary_key: true
      add :season_id, references(:seasons, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :title, :string, null: false
      add :overview, :text
      add :air_date, :date
      add :still_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:episodes, [:season_id, :number])
    create constraint(:episodes, :episodes_number_valid, check: "number > 0")
  end

  def down do
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM catalog_entries WHERE kind <> 'movie') THEN
        RAISE EXCEPTION 'cannot remove series hierarchy while series content exists';
      END IF;
    END $$;
    """

    drop table(:episodes)
    drop table(:seasons)
    drop table(:series)
    drop constraint(:catalog_entries, :catalog_entries_kind_valid)
    drop constraint(:catalog_entries, :catalog_entries_resource_type_valid)
    create constraint(:catalog_entries, :catalog_entries_kind_valid, check: "kind = 'movie'")

    create constraint(:catalog_entries, :catalog_entries_resource_type_valid,
             check: "resource_type = 'movie'"
           )
  end
end

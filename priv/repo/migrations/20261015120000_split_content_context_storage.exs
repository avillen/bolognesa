defmodule Bolognesa.Repo.Migrations.SplitContentContextStorage do
  use Ecto.Migration

  def up do
    drop table(:identification_entries)
    execute "DROP FUNCTION validate_identification_entry()"
    drop table(:media_identification_events)
    drop table(:media_identifications)
    drop table(:episodes)
    drop table(:seasons)
    drop table(:series)
    drop table(:movies)
    drop table(:catalog_entries)

    create table(:movies) do
      add :provider, :string, null: false
      add :provider_id, :bigint, null: false
      add :title, :string, null: false
      add :original_title, :string
      add :year, :integer
      add :overview, :text
      add :poster_path, :string
      add :backdrop_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:series) do
      add :provider, :string, null: false
      add :provider_id, :bigint, null: false
      add :title, :string, null: false
      add :year, :integer
      add :overview, :text
      add :poster_path, :string
      add :backdrop_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:seasons) do
      add :provider, :string, null: false
      add :provider_id, :bigint, null: false
      add :series_id, references(:series, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :title, :string
      add :poster_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    create table(:episodes) do
      add :provider, :string, null: false
      add :provider_id, :bigint, null: false
      add :season_id, references(:seasons, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :title, :string, null: false
      add :overview, :text
      add :air_date, :date
      add :still_path, :string
      timestamps(type: :utc_datetime_usec)
    end

    for table <- [:movies, :series, :seasons, :episodes] do
      create unique_index(table, [:provider, :provider_id])
      create constraint(table, :"#{table}_provider_valid", check: "provider = 'tmdb'")
      create constraint(table, :"#{table}_provider_id_positive", check: "provider_id > 0")
      create constraint(table, :"#{table}_title_nonempty", check: "length(trim(title)) > 0")
    end

    create unique_index(:seasons, [:series_id, :number])
    create unique_index(:episodes, [:season_id, :number])
    create constraint(:seasons, :seasons_number_valid, check: "number >= 0")
    create constraint(:episodes, :episodes_number_valid, check: "number > 0")

    for table <- [:movie_identifications, :series_identifications] do
      create table(table) do
        add :media_file_id, references(:media_files, on_delete: :delete_all), null: false
        add :state, :string, null: false, default: "pending"
        add :origin, :string
        add :observed_revision, :bigint, null: false
        add :token, :uuid, null: false
        add :needs_review, :boolean, null: false, default: false
        add :failure_reason, :string
        add :candidate_data, :map, null: false, default: %{items: []}
        add :job_id, :bigint
        add :started_at, :utc_datetime_usec
        add :finished_at, :utc_datetime_usec
        timestamps(type: :utc_datetime_usec)
      end

      create unique_index(table, [:media_file_id])
      create index(table, [:job_id])

      create constraint(table, :"#{table}_state_valid",
               check:
                 "state IN ('pending','automatic','manual','manual_unidentified','failed','unmatched')"
             )

      create constraint(table, :"#{table}_revision_positive", check: "observed_revision > 0")
    end

    alter table(:movie_identifications) do
      add :movie_id, references(:movies, on_delete: :restrict)
    end

    create index(:movie_identifications, [:movie_id])

    create constraint(:movie_identifications, :movie_identifications_choice_valid,
             check:
               "(state IN ('automatic','manual') AND movie_id IS NOT NULL) OR (state NOT IN ('automatic','manual') AND movie_id IS NULL)"
           )

    create table(:series_identification_episodes) do
      add :identification_id, references(:series_identifications, on_delete: :delete_all),
        null: false

      add :episode_id, references(:episodes, on_delete: :restrict), null: false
      add :position, :integer, null: false
    end

    create unique_index(:series_identification_episodes, [:identification_id, :episode_id],
             name: :series_identification_episode_unique
           )

    create unique_index(:series_identification_episodes, [:identification_id, :position])
    create index(:series_identification_episodes, [:episode_id])

    create constraint(
             :series_identification_episodes,
             :series_identification_episodes_position_positive, check: "position > 0")

    execute """
    CREATE FUNCTION validate_series_identification_episode() RETURNS trigger AS $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM series_identifications WHERE id = NEW.identification_id AND state IN ('automatic','manual')) THEN
        RAISE EXCEPTION 'association requires a confirmed decision' USING ERRCODE = '23514', CONSTRAINT = 'series_identification_episodes_confirmed';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER series_identification_episodes_confirmed
    BEFORE INSERT OR UPDATE ON series_identification_episodes
    FOR EACH ROW EXECUTE FUNCTION validate_series_identification_episode();
    """

    for table <- [:movie_identification_events, :series_identification_events] do
      create table(table) do
        add :media_file_id, references(:media_files, on_delete: :delete_all), null: false
        add :token, :uuid, null: false
        add :delivered_at, :utc_datetime_usec
        timestamps(type: :utc_datetime_usec)
      end

      create unique_index(table, [:media_file_id, :token])
      create index(table, [:id], where: "delivered_at IS NULL", name: :"#{table}_pending_index")
    end
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "Content context rebuild is irreversible; rebuild the database for the target version"
  end
end

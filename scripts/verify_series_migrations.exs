# Run: MIX_ENV=test mix run --no-start scripts/verify_series_migrations.exs
# Only this dedicated Repo is migrated. The application Repo is never the verification target.
defmodule Bolognesa.SeriesMigrationCheckRepo do
  use Ecto.Repo, otp_app: :bolognesa, adapter: Ecto.Adapters.Postgres
end

defmodule Bolognesa.SeriesMigrationCheck do
  @moduledoc false
  alias Bolognesa.Identification.Domain.{
    EpisodeDetails,
    EpisodeSelection,
    SeasonDetails,
    SeriesDetails
  }

  alias Bolognesa.Identification.Infrastructure.Persistence.IdentifiedSeriesWriter
  alias Bolognesa.SeriesMigrationCheckRepo, as: CheckRepo
  @database "bolognesa_series_migration_check"
  @baseline 20_261_011_104_533
  @associations 20_261_011_113_855
  @hierarchy 20_261_011_114_509

  @spec run() :: :ok
  def run do
    database = System.get_env("SERIES_MIGRATION_DATABASE", @database)
    if database != @database, do: raise("Refusing non-disposable series migration database")
    if Mix.env() != :test, do: raise("Run with MIX_ENV=test")

    if Process.whereis(Bolognesa.Supervisor) || Process.whereis(Bolognesa.Repo),
      do: raise("Run with --no-start; Bolognesa must remain stopped")

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    config = [
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      database: database,
      pool_size: 2,
      log: false
    ]

    Application.put_env(:bolognesa, CheckRepo, config)
    migrations = migrations()

    for seeded? <- [true, false] do
      reset_storage!(config)
      {:ok, pid} = CheckRepo.start_link()

      try do
        migrate(migrations, :up, to: @baseline)
        if seeded?, do: seed!()
        before = snapshot(:old)
        migrate(migrations, :up, all: true)
        equal!(snapshot(:new), before, "forward preservation")

        check!(
          query("SELECT count(*) FROM libraries WHERE content_type <> 'movie'").rows == [[0]],
          "existing library type"
        )

        assert_integrity!()
        id = insert_movie!()
        check!(id > if(seeded?, do: 900_000, else: 0), "catalog identity sequence")
        after_insert = snapshot(:new)
        verify_multiple_movie_rollback!(migrations)
        verify_rejected_rollback!(migrations)
        equal!(snapshot(:new), after_insert, "rejected rollback fixture cleanup")
        migrate(migrations, :down, step: 3)
        equal!(snapshot(:old), after_insert, "admissible rollback")
        restored = snapshot(:old)
        migrate(migrations, :up, all: true)
        equal!(snapshot(:new), restored, "reapply preservation")
        assert_integrity!()
        next_id = insert_movie!(70_002)
        check!(next_id > id, "reapplied sequence")

        IO.puts(
          "Series migrations: #{if seeded?, do: "seeded", else: "empty"} round trip and rollback rejection passed"
        )
      after
        Supervisor.stop(pid)
      end
    end

    IO.puts("Series migration verification passed")
    :ok
  end

  defp migrations do
    Application.app_dir(:bolognesa, "priv/repo/migrations")
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn file ->
      {version, _} = Integer.parse(Path.basename(file))
      [{module, _}] = Code.compile_file(file)
      {version, module}
    end)
  end

  defp migrate(migrations, direction, opts),
    do:
      Ecto.Migrator.run(
        CheckRepo,
        migrations,
        direction,
        Keyword.merge(opts, log: false, log_migrations_sql: false)
      )

  defp reset_storage!(config) do
    case Ecto.Adapters.Postgres.storage_down(config) do
      :ok -> :ok
      {:error, :already_down} -> :ok
      _ -> raise "Disposable series database drop failed"
    end

    case Ecto.Adapters.Postgres.storage_up(config) do
      :ok -> :ok
      _ -> raise "Disposable series database creation failed"
    end
  end

  defp seed! do
    {:ok, _} =
      CheckRepo.transaction(fn ->
        query(
          "INSERT INTO libraries (id, name, path, inserted_at, updated_at) VALUES (1, 'Synthetic migration', '/synthetic-series-check', now(), now())"
        )

        for {id, external} <- [{7, 1007}, {41, 1041}, {900_000, 1_900_000}] do
          query(
            "INSERT INTO catalog_entries (id, kind, provider, resource_type, provider_id, inserted_at, updated_at) VALUES ($1, 'movie', 'tmdb', 'movie', $2, now(), now())",
            [id, external]
          )

          query(
            "INSERT INTO movies (id, title, original_title, year, overview, poster_path, backdrop_path, inserted_at, updated_at) VALUES ($1, 'Synthetic movie', 'Synthetic original', 2001, 'Synthetic overview', '/synthetic.jpg', '/synthetic-background.jpg', now(), now())",
            [id]
          )
        end

        for {{state, entry, origin}, file_id} <-
              Enum.with_index(
                [
                  {"manual", 7, "manual"},
                  {"automatic", 7, "automatic"},
                  {"manual", 900_000, "manual"},
                  {"pending", 41, "automatic"},
                  {"failed", 900_000, "automatic"},
                  {"manual_unidentified", nil, "manual"}
                ],
                1
              ) do
          token = Ecto.UUID.generate()

          query(
            "INSERT INTO media_files (id, library_id, relative_path, size_bytes, modified_at, availability, revision, last_seen_generation) VALUES ($1, 1, $2, 16, now(), 'available', 3, $3::text::uuid)",
            [file_id, "Synthetic#{file_id}.mp4", Ecto.UUID.generate()]
          )

          query(
            "INSERT INTO media_identifications (id, media_file_id, catalog_entry_id, state, origin, observed_revision, token, needs_review, failure_reason, candidate_data, inserted_at, updated_at) VALUES ($1, $1, $2, $3, $4, 3, $5::text::uuid, true, $6, $7::jsonb, now(), now())",
            [
              file_id,
              entry,
              state,
              origin,
              token,
              if(state == "failed", do: "not_configured"),
              Jason.encode!(%{items: [%{provider_id: 1007, title: "Synthetic candidate"}]})
            ]
          )

          if state == "pending" do
            query(
              "INSERT INTO media_identification_events (media_file_id, token, inserted_at, updated_at) VALUES ($1, $2::text::uuid, now(), now())",
              [file_id, token]
            )

            job =
              CheckRepo.insert!(
                Oban.Job.new(%{"file_id" => file_id, "token" => token},
                  worker: Bolognesa.Identification.Infrastructure.Jobs.IdentificationWorker,
                  queue: :identifications
                ),
                log: false
              )

            query("UPDATE media_identifications SET job_id = $1 WHERE id = $2", [job.id, file_id])
          end
        end

        for table <- ["catalog_entries", "libraries", "media_files", "media_identifications"] do
          query(
            "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), COALESCE(MAX(id), 1), MAX(id) IS NOT NULL) FROM #{table}"
          )
        end
      end)
  end

  defp insert_movie!(external \\ 70_001) do
    {:ok, id} =
      CheckRepo.transaction(fn ->
        [[id]] =
          query(
            "INSERT INTO catalog_entries (kind, provider, resource_type, provider_id, inserted_at, updated_at) VALUES ('movie', 'tmdb', 'movie', $1, now(), now()) RETURNING id",
            [external]
          ).rows

        query(
          "INSERT INTO movies (id, title, year, inserted_at, updated_at) VALUES ($1, 'New synthetic movie', 2002, now(), now())",
          [id]
        )

        library = library!("movie", external)
        file = file!(library, "New synthetic.mp4")

        [[decision]] =
          query(
            "INSERT INTO media_identifications (media_file_id, state, origin, observed_revision, token, inserted_at, updated_at) VALUES ($1, 'manual', 'manual', 1, $2::text::uuid, now(), now()) RETURNING id",
            [file, Ecto.UUID.generate()]
          ).rows

        query(
          "INSERT INTO identification_entries (identification_id, catalog_entry_id, position) VALUES ($1, $2, 1)",
          [decision, id]
        )

        id
      end)

    id
  end

  defp verify_multiple_movie_rollback!(migrations) do
    [[entry]] =
      query(
        "INSERT INTO catalog_entries (kind, provider, resource_type, provider_id, inserted_at, updated_at) VALUES ('movie', 'tmdb', 'movie', 80099, now(), now()) RETURNING id"
      ).rows

    query(
      "INSERT INTO movies (id, title, inserted_at, updated_at) VALUES ($1, 'Second synthetic movie', now(), now())",
      [entry]
    )

    [[decision]] =
      query(
        "SELECT identification_id FROM identification_entries ORDER BY identification_id LIMIT 1"
      ).rows

    query(
      "INSERT INTO identification_entries (identification_id, catalog_entry_id, position) VALUES ($1, $2, 2)",
      [decision, entry]
    )

    before = snapshot(:new)
    reject_down!(migrations, @associations)
    equal!(snapshot(:new), before, "multiple movie associations intact")
    query("DELETE FROM identification_entries WHERE catalog_entry_id = $1", [entry])
    query("DELETE FROM movies WHERE id = $1", [entry])
    query("DELETE FROM catalog_entries WHERE id = $1", [entry])
  end

  defp verify_rejected_rollback!(migrations) do
    library = library!("series", 80_001)
    file = file!(library, "Synthetic S00E01E02.mkv")

    [[decision]] =
      query(
        "INSERT INTO media_identifications (media_file_id, state, origin, observed_revision, token, inserted_at, updated_at) VALUES ($1, 'manual_unidentified', 'manual', 1, $2::text::uuid, now(), now()) RETURNING id",
        [file, Ecto.UUID.generate()]
      ).rows

    before_unidentified = snapshot(:new)
    empty_hierarchy = hierarchy_snapshot()
    # Even an as-yet unidentified series library must not silently lose its content type.
    for version <- [@associations, @hierarchy, 20_261_011_113_609] do
      reject_down!(migrations, version)
      equal!(snapshot(:new), before_unidentified, "unidentified series decisions intact")
      equal!(hierarchy_snapshot(), empty_hierarchy, "unidentified series schema intact")
    end

    series = %SeriesDetails{provider_id: 201, title: "Synthetic series"}

    episodes =
      for number <- [1, 2],
          do: %EpisodeDetails{
            provider_id: 20_100 + number,
            season_number: 0,
            number: number,
            title: "Synthetic episode #{number}"
          }

    season = %SeasonDetails{
      provider_id: 2010,
      series_provider_id: 201,
      number: 0,
      title: "Specials",
      episodes: episodes
    }

    {:ok, selection} = EpisodeSelection.new(series, season, [1, 2])

    {:ok, ids} =
      CheckRepo.transaction(fn ->
        ids = IdentifiedSeriesWriter.upsert!(selection, CheckRepo)
        query("UPDATE media_identifications SET state = 'manual' WHERE id = $1", [decision])

        for {id, position} <- Enum.with_index(ids, 1),
            do:
              query(
                "INSERT INTO identification_entries (identification_id, catalog_entry_id, position) VALUES ($1, $2, $3)",
                [decision, id, position]
              )

        ids
      end)

    check!(length(ids) == 2, "complete episode writer")
    state = snapshot(:new)
    hierarchy = hierarchy_snapshot()

    for version <- [@associations, @hierarchy] do
      reject_down!(migrations, version)
      equal!(snapshot(:new), state, "rejected rollback decisions intact")
      equal!(hierarchy_snapshot(), hierarchy, "rejected rollback hierarchy intact")
    end

    query("DELETE FROM media_identifications WHERE id = $1", [decision])
    query("DELETE FROM media_files WHERE id = $1", [file])
    query("DELETE FROM libraries WHERE id = $1", [library])
    query("DELETE FROM episodes")
    query("DELETE FROM seasons")
    query("DELETE FROM series")
    query("DELETE FROM catalog_entries WHERE kind <> 'movie'")
  end

  defp reject_down!(migrations, version) do
    {^version, module} = Enum.find(migrations, fn {id, _} -> id == version end)

    rejected? =
      try do
        Ecto.Migrator.down(CheckRepo, version, module, log: false, log_migrations_sql: false)
        false
      rescue
        error in Postgrex.Error -> String.contains?(Exception.message(error), "cannot")
      end

    check!(rejected?, "rollback must refuse series without data loss")
  end

  defp hierarchy_snapshot do
    Map.new(
      [
        "catalog_entries",
        "series",
        "seasons",
        "episodes",
        "identification_entries",
        "schema_migrations"
      ],
      fn table -> {table, query("SELECT * FROM #{table} ORDER BY 1").rows} end
    )
  end

  defp library!(type, external) do
    [[id]] =
      query(
        "INSERT INTO libraries (name, path, content_type, inserted_at, updated_at) VALUES ('Synthetic', $1, $2, now(), now()) RETURNING id",
        ["/synthetic-#{external}", type]
      ).rows

    id
  end

  defp file!(library, name) do
    [[id]] =
      query(
        "INSERT INTO media_files (library_id, relative_path, size_bytes, modified_at, last_seen_generation) VALUES ($1, $2, 16, now(), $3::text::uuid) RETURNING id",
        [library, name, Ecto.UUID.generate()]
      ).rows

    id
  end

  defp snapshot(stage) do
    relation =
      case stage do
        :old ->
          "SELECT id, catalog_entry_id, 1 FROM media_identifications WHERE catalog_entry_id IS NOT NULL AND state IN ('automatic','manual') ORDER BY id"

        :new ->
          "SELECT identification_id, catalog_entry_id, position FROM identification_entries ORDER BY identification_id, position"
      end

    %{
      movies:
        query(
          "SELECT m.id, e.provider, e.provider_id, m.title, m.original_title, m.year, m.overview, m.poster_path, m.backdrop_path, m.inserted_at, m.updated_at FROM movies m JOIN catalog_entries e ON e.id = m.id ORDER BY m.id"
        ).rows,
      decisions:
        query(
          "SELECT id, media_file_id, state, origin, observed_revision, token, needs_review, failure_reason, candidate_data, job_id, started_at, finished_at, inserted_at, updated_at FROM media_identifications ORDER BY id"
        ).rows,
      associations: query(relation).rows,
      libraries:
        query("SELECT id, name, path, inserted_at, updated_at FROM libraries ORDER BY id").rows,
      files: query("SELECT * FROM media_files ORDER BY id").rows,
      events: query("SELECT * FROM media_identification_events ORDER BY id").rows,
      jobs: query("SELECT id, state, args, worker, queue FROM oban_jobs ORDER BY id").rows
    }
  end

  defp assert_integrity! do
    [[0]] =
      query(
        "SELECT count(*) FROM movies m LEFT JOIN catalog_entries e ON e.id = m.id WHERE e.id IS NULL OR e.kind <> 'movie'"
      ).rows

    [[0]] =
      query(
        "SELECT count(*) FROM identification_entries r LEFT JOIN media_identifications d ON d.id = r.identification_id WHERE d.id IS NULL OR d.state NOT IN ('automatic','manual') OR r.position <= 0"
      ).rows

    [[0]] =
      query(
        "SELECT count(*) FROM information_schema.columns WHERE table_name = 'media_identifications' AND column_name = 'catalog_entry_id'"
      ).rows
  end

  defp query(sql, params \\ []), do: Ecto.Adapters.SQL.query!(CheckRepo, sql, params, log: false)
  defp equal!(actual, expected, reason), do: check!(actual == expected, reason)
  defp check!(true, _), do: :ok
  defp check!(false, reason), do: raise("Series migration verification failed: #{reason}")
end

Bolognesa.SeriesMigrationCheck.run()

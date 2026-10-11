# Run only against the disposable database named below. The application Repo is never migrated.
defmodule Bolognesa.CatalogMigrationCheckRepo do
  use Ecto.Repo, otp_app: :bolognesa, adapter: Ecto.Adapters.Postgres
end

defmodule Bolognesa.CatalogMigrationCheck do
  @moduledoc false
  alias Bolognesa.CatalogMigrationCheckRepo, as: CheckRepo
  @database "bolognesa_catalog_migration_check"
  @previous 20_261_007_201_745

  @spec run() :: :ok
  def run do
    database = System.get_env("CATALOG_MIGRATION_DATABASE", @database)
    if database != @database, do: raise("Refusing non-disposable database")
    if Mix.env() != :test, do: raise("Run with MIX_ENV=test")

    config = [
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      database: database,
      pool_size: 2,
      log: false
    ]

    Application.put_env(:bolognesa, CheckRepo, config)
    path = Application.app_dir(:bolognesa, "priv/repo/migrations")

    migrations =
      path
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(fn file ->
        {version, _} = Integer.parse(Path.basename(file))
        [{module, _}] = Code.compile_file(file)
        {version, module}
      end)

    for seeded? <- [true, false] do
      reset_storage!(config)
      {:ok, pid} = CheckRepo.start_link()

      try do
        migrate(migrations, :up, to: @previous)
        if seeded?, do: seed!()
        before = snapshot(:old)
        migrate(migrations, :up, all: true)
        equal!(snapshot(:new), before, "forward preservation")
        assert_integrity!()
        new_id = insert_movie!()
        check!(new_id > if(seeded?, do: 900_000, else: 0), "identity sequence")
        after_insert = snapshot(:new)
        migrate(migrations, :down, step: 3)
        equal!(snapshot(:old), after_insert, "rollback preservation")
        # Verify the restored movie sequence without retaining an extra synthetic row.
        {:ok, _} =
          CheckRepo.transaction(fn ->
            [[id]] =
              query(
                "INSERT INTO movies (provider, provider_id, title, inserted_at, updated_at) VALUES ('tmdb', 70002, 'Sequence check', now(), now()) RETURNING id"
              ).rows

            check!(id > new_id, "restored movie sequence")
            :ok
          end)

        restored = snapshot(:old)
        migrate(migrations, :up, all: true)
        equal!(snapshot(:new), restored, "reapply preservation")
        assert_integrity!()
        last_id = insert_movie!(70003)
        check!(last_id > new_id, "reapplied identity sequence")

        IO.puts(
          "Catalog migrations: #{if seeded?, do: "seeded", else: "empty"} round trip passed; movies=#{length(snapshot(:new).movies)}"
        )
      after
        Supervisor.stop(pid)
      end
    end

    IO.puts("Catalog migration verification passed")
    :ok
  end

  defp reset_storage!(config) do
    case Ecto.Adapters.Postgres.storage_down(config) do
      :ok -> :ok
      {:error, :already_down} -> :ok
      {:error, _} -> raise "Disposable database drop failed"
    end

    case Ecto.Adapters.Postgres.storage_up(config) do
      :ok -> :ok
      {:error, _} -> raise "Disposable database creation failed"
    end
  end

  defp migrate(migrations, direction, opts) do
    Ecto.Migrator.run(
      CheckRepo,
      migrations,
      direction,
      Keyword.merge(opts, log: false, log_migrations_sql: false)
    )
  end

  defp seed! do
    {:ok, _} =
      CheckRepo.transaction(fn ->
        query(
          "INSERT INTO libraries (id, name, path, inserted_at, updated_at) VALUES (1, 'Synthetic migration', '/synthetic-catalog-check', now(), now())"
        )

        for {id, provider_id} <- [{7, 1007}, {41, 1041}, {900_000, 1_900_000}] do
          query(
            "INSERT INTO movies (id, provider, provider_id, title, original_title, year, overview, poster_path, backdrop_path, inserted_at, updated_at) VALUES ($1, 'tmdb', $2, 'Synthetic movie', 'Synthetic original', 2001, 'Synthetic overview', '/synthetic.jpg', '/synthetic-background.jpg', now(), now())",
            [id, provider_id]
          )
        end

        choices = [
          {:manual, 7, :manual},
          {:automatic, 7, :automatic},
          {:manual_unidentified, nil, :manual},
          {:pending, 41, :automatic},
          {:failed, 900_000, :automatic}
        ]

        for {{state, movie_id, origin}, file_id} <- Enum.with_index(choices, 1) do
          token = Ecto.UUID.generate()

          query(
            "INSERT INTO media_files (id, library_id, relative_path, size_bytes, modified_at, availability, revision, last_seen_generation) VALUES ($1, 1, $2, 16, now(), 'available', 3, $3::text::uuid)",
            [file_id, "Synthetic#{file_id}.mp4", Ecto.UUID.generate()]
          )

          query(
            "INSERT INTO media_identifications (id, media_file_id, movie_id, state, origin, observed_revision, token, needs_review, failure_reason, candidate_data, inserted_at, updated_at) VALUES ($1, $1, $2, $3, $4, 3, $5::text::uuid, true, $6, $7::jsonb, now(), now())",
            [
              file_id,
              movie_id,
              Atom.to_string(state),
              Atom.to_string(origin),
              token,
              if(state == :failed, do: "not_configured", else: nil),
              Jason.encode!(%{items: [%{provider_id: 1007, title: "Synthetic candidate"}]})
            ]
          )

          if state == :pending do
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

        for table <- ["libraries", "media_files", "media_identifications"] do
          query(
            "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), COALESCE(MAX(id), 1), MAX(id) IS NOT NULL) FROM #{table}"
          )
        end
      end)
  end

  defp insert_movie!(provider_id \\ 70001) do
    {:ok, id} =
      CheckRepo.transaction(fn ->
        [[id]] =
          query(
            "INSERT INTO catalog_entries (kind, provider, resource_type, provider_id, inserted_at, updated_at) VALUES ('movie', 'tmdb', 'movie', $1, now(), now()) RETURNING id",
            [provider_id]
          ).rows

        query(
          "INSERT INTO movies (id, title, year, inserted_at, updated_at) VALUES ($1, 'New synthetic movie', 2002, now(), now())",
          [id]
        )

        # A post-migration association must also survive rollback.
        [[library_id]] =
          query(
            "INSERT INTO libraries (name, path, inserted_at, updated_at) VALUES ('New synthetic', $1, now(), now()) RETURNING id",
            ["/synthetic-new-#{provider_id}"]
          ).rows

        [[file_id]] =
          query(
            "INSERT INTO media_files (library_id, relative_path, size_bytes, modified_at, last_seen_generation) VALUES ($1, $2, 16, now(), $3::text::uuid) RETURNING id",
            [library_id, "New synthetic.mp4", Ecto.UUID.generate()]
          ).rows

        query(
          "INSERT INTO media_identifications (media_file_id, catalog_entry_id, state, origin, observed_revision, token, inserted_at, updated_at) VALUES ($1, $2, 'manual', 'manual', 1, $3::text::uuid, now(), now())",
          [file_id, id, Ecto.UUID.generate()]
        )

        id
      end)

    id
  end

  defp snapshot(stage) do
    {provider, join, reference} =
      case stage do
        :old ->
          {"m.provider, m.provider_id", "", "movie_id"}

        :new ->
          {"e.provider, e.provider_id", "JOIN catalog_entries e ON e.id = m.id",
           "catalog_entry_id"}
      end

    %{
      movies:
        query(
          "SELECT m.id, #{provider}, m.title, m.original_title, m.year, m.overview, m.poster_path, m.backdrop_path, m.inserted_at, m.updated_at FROM movies m #{join} ORDER BY m.id"
        ).rows,
      identifications:
        query(
          "SELECT id, media_file_id, #{reference}, state, origin, observed_revision, token, needs_review, failure_reason, candidate_data, job_id, started_at, finished_at, inserted_at, updated_at FROM media_identifications ORDER BY id"
        ).rows,
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
        "SELECT count(*) FROM media_identifications i LEFT JOIN movies m ON m.id = i.catalog_entry_id WHERE i.catalog_entry_id IS NOT NULL AND m.id IS NULL"
      ).rows

    [[0]] =
      query(
        "SELECT count(*) FROM information_schema.columns WHERE table_name = 'movies' AND column_name IN ('provider', 'provider_id')"
      ).rows

    constraints =
      query(
        "SELECT conname FROM pg_constraint WHERE conrelid IN ('catalog_entries'::regclass, 'movies'::regclass, 'media_identifications'::regclass)"
      ).rows
      |> List.flatten()

    for name <- [
          "catalog_entries_kind_valid",
          "catalog_entries_provider_valid",
          "catalog_entries_resource_type_valid",
          "catalog_entries_provider_id_positive",
          "movies_id_fkey",
          "media_identifications_catalog_entry_id_fkey",
          "media_identifications_choice_valid"
        ] do
      check!(name in constraints, "missing constraint")
    end

    indexes =
      query(
        "SELECT indexname FROM pg_indexes WHERE tablename IN ('catalog_entries', 'media_identifications')"
      ).rows
      |> List.flatten()

    check!(
      "catalog_entries_provider_resource_type_provider_id_index" in indexes,
      "external uniqueness"
    )

    check!("media_identifications_catalog_entry_id_index" in indexes, "association index")
  end

  defp query(sql, params \\ []), do: Ecto.Adapters.SQL.query!(CheckRepo, sql, params, log: false)
  defp equal!(actual, expected, reason), do: check!(actual == expected, reason)
  defp check!(true, _reason), do: :ok
  defp check!(false, reason), do: raise("Catalog migration verification failed: #{reason}")
end

Bolognesa.CatalogMigrationCheck.run()

# MIX_ENV=test mix run --no-start scripts/verify_content_context_migrations.exs
# This verifier may only recreate its dedicated disposable database.
defmodule Bolognesa.ContentContextMigrationCheckRepo do
  use Ecto.Repo, otp_app: :bolognesa, adapter: Ecto.Adapters.Postgres
end

defmodule Bolognesa.ContentContextMigrationCheck do
  @moduledoc false
  alias Bolognesa.ContentContextMigrationCheckRepo, as: CheckRepo
  @database "bolognesa_content_context_migration_check"

  @spec run() :: :ok
  def run do
    database = System.get_env("CONTENT_CONTEXT_MIGRATION_DATABASE", @database)
    if database != @database, do: raise("Refusing non-disposable database")
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

    for pass <- 1..2 do
      case Ecto.Adapters.Postgres.storage_down(config) do
        :ok -> :ok
        {:error, :already_down} -> :ok
        _ -> raise "Disposable database drop failed"
      end

      :ok = Ecto.Adapters.Postgres.storage_up(config)
      {:ok, pid} = CheckRepo.start_link()

      try do
        Ecto.Migrator.run(CheckRepo, migrations, :up, all: true, log: false)

        for table <-
              ~w(movies series seasons episodes movie_identifications movie_identification_events series_identifications series_identification_episodes series_identification_events) do
          [[true]] = query("SELECT to_regclass($1) IS NOT NULL", [table]).rows
        end

        for table <-
              ~w(catalog_entries media_identifications identification_entries media_identification_events) do
          [[nil]] = query("SELECT to_regclass($1)", [table]).rows
        end

        [[nil]] = query("SELECT to_regprocedure('validate_identification_entry()')").rows

        [[movie]] =
          query(
            "INSERT INTO movies (provider, provider_id, title, inserted_at, updated_at) VALUES ('tmdb', 1, 'Synthetic movie', now(), now()) RETURNING id"
          ).rows

        [[series]] =
          query(
            "INSERT INTO series (provider, provider_id, title, inserted_at, updated_at) VALUES ('tmdb', 1, 'Synthetic series', now(), now()) RETURNING id"
          ).rows

        true = movie == series

        try do
          Ecto.Migrator.run(CheckRepo, migrations, :down, step: 1, log: false)
          raise "Reverse migration unexpectedly succeeded"
        rescue
          error in Ecto.MigrationError ->
            true = String.contains?(error.message, "irreversible")
        end

        IO.puts(
          "Content context migrations: rebuild #{pass} passed; independent identities and refused rollback verified"
        )
      after
        Supervisor.stop(pid)
      end
    end

    :ok
  end

  defp query(sql, params \\ []), do: Ecto.Adapters.SQL.query!(CheckRepo, sql, params, log: false)
end

Bolognesa.ContentContextMigrationCheck.run()

# Run: MIX_ENV=test mix run --no-start scripts/verify_accounts_migration.exs
# Uses only the disposable database below; never migrates the application Repo.
defmodule Bolognesa.AccountsMigrationCheckRepo do
  use Ecto.Repo, otp_app: :bolognesa, adapter: Ecto.Adapters.Postgres
end

defmodule Bolognesa.AccountsMigrationCheck do
  @moduledoc false
  alias Bolognesa.AccountsMigrationCheckRepo, as: CheckRepo

  @spec run() :: :ok
  def run do
    if Mix.env() != :test or Process.whereis(Bolognesa.Repo),
      do: raise("Run with MIX_ENV=test mix run --no-start")

    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    config = [
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      database: "bolognesa_accounts_migration_check",
      pool_size: 2,
      log: false
    ]

    Application.put_env(:bolognesa, CheckRepo, config)
    Ecto.Adapters.Postgres.storage_down(config)
    :ok = Ecto.Adapters.Postgres.storage_up(config)
    {:ok, pid} = CheckRepo.start_link()

    try do
      path = Application.app_dir(:bolognesa, "priv/repo/migrations")

      migrations =
        for file <- [
              "20261002191049_create_identity_tables.exs",
              "20261002191510_create_identity_sessions.exs",
              "20261011193621_add_user_locale.exs",
              "20261016120000_rename_identity_to_accounts.exs"
            ] do
          {version, _} = Integer.parse(file)
          [{module, _}] = Code.compile_file(Path.join(path, file))
          {version, module}
        end

      for seeded? <- [false, true] do
        Ecto.Migrator.run(CheckRepo, migrations, :up, to: 20_261_011_193_621, log: false)

        if seeded? do
          query!(
            "INSERT INTO identity_users (id, name, email, role, hashed_password, locale, inserted_at, updated_at) VALUES (900000, 'Example', 'example@example.com', 'admin', 'test-hash', 'en', now(), now())"
          )

          query!(
            "INSERT INTO identity_sessions (user_id, token_hash, expires_at, inserted_at) VALUES (900000, decode('abcd', 'hex'), now() + interval '1 day', now())"
          )
        end

        before = snapshot("identity")
        Ecto.Migrator.run(CheckRepo, migrations, :up, all: true, log: false)
        ^before = snapshot("accounts")

        [[[]]] =
          query!(
            "SELECT ARRAY(SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'identity_%')"
          ).rows

        Ecto.Migrator.run(CheckRepo, migrations, :down, step: 1, log: false)
        ^before = snapshot("identity")
        Ecto.Migrator.run(CheckRepo, migrations, :up, all: true, log: false)
        ^before = snapshot("accounts")
        Ecto.Migrator.run(CheckRepo, migrations, :down, all: true, log: false)
      end

      IO.puts(
        "Accounts migration passed empty/seeded upgrade, rollback, and reapplication checks"
      )
    after
      GenServer.stop(pid)
      :ok = Ecto.Adapters.Postgres.storage_down(config)
    end
  end

  defp snapshot(prefix) do
    for suffix <- ["users", "sessions"],
        do: query!("SELECT * FROM #{prefix}_#{suffix} ORDER BY id").rows
  end

  defp query!(sql), do: Ecto.Adapters.SQL.query!(CheckRepo, sql, [])
end

Bolognesa.AccountsMigrationCheck.run()

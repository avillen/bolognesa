defmodule Bolognesa.DirectJobsMigrationCheckRepo do
  use Ecto.Repo, otp_app: :bolognesa, adapter: Ecto.Adapters.Postgres
end

defmodule Bolognesa.DirectJobsMigrationCheck do
  @moduledoc false
  alias Bolognesa.DirectJobsMigrationCheckRepo, as: CheckRepo
  @versions %{inspection: 20_261_017_120_000, music: 20_261_017_130_000, video: 20_261_017_140_000}

  @spec run(:inspection | :music | :video) :: :ok
  def run(kind) do
    if Mix.env() != :test or Process.whereis(Bolognesa.Repo),
      do: raise("Run with MIX_ENV=test mix run --no-start")

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    config = [username: "postgres", password: "postgres", hostname: "localhost",
      database: "bolognesa_direct_jobs_migration_check", pool_size: 2, log: false]
    Application.put_env(:bolognesa, CheckRepo, config)
    migrations = for file <- Path.wildcard(Application.app_dir(:bolognesa, "priv/repo/migrations/*.exs")) |> Enum.sort() do
      {version, _} = Integer.parse(Path.basename(file))
      [{module, _}] = Code.compile_file(file)
      {version, module}
    end
    version = Map.fetch!(@versions, kind)

    for seeded? <- [false, true] do
      Ecto.Adapters.Postgres.storage_down(config)
      :ok = Ecto.Adapters.Postgres.storage_up(config)
      {:ok, pid} = CheckRepo.start_link()
      try do
        Ecto.Migrator.run(CheckRepo, migrations, :up, to: version - 1, log: false)
        expected = if seeded?, do: seed(kind), else: []
        Ecto.Migrator.run(CheckRepo, migrations, :up, to: version, log: false)
        verify(kind, expected)
        try do
          Ecto.Migrator.run(CheckRepo, migrations, :down, step: 1, log: false)
          raise "Reverse migration unexpectedly succeeded"
        rescue
          error in Ecto.MigrationError -> true = String.contains?(error.message, "irreversible")
        end
        IO.puts("#{kind} jobs migration: #{if seeded?, do: "seeded", else: "empty"} upgrade and refused reversal passed")
      after
        Supervisor.stop(pid)
        :ok = Ecto.Adapters.Postgres.storage_down(config)
      end
    end
    :ok
  end

  defp seed(:inspection) do
    for n <- 1..106 do
      file = file("movie", n)
      token = Ecto.UUID.generate()
      delivered = n in [102, 103, 104]
      state = if n == 105, do: "succeeded", else: "pending"
      linked = if n in [102, 103], do: job("Libraries.Infrastructure.Jobs.InspectionWorker", "media_inspections", %{"media_file_id" => file, "token" => token}), else: nil
      query("INSERT INTO media_inspections (media_file_id, token, observed_revision, state, job_id, inserted_at, updated_at) VALUES ($1,$2::text::uuid,1,$3,$4,now(),now())", [file, token, state, linked])
      query("INSERT INTO media_inspection_events (media_file_id,token,delivered_at,inserted_at,updated_at) VALUES ($1,$2::text::uuid,CASE WHEN $3 THEN now() END,now(),now())", [file, if(n == 106, do: Ecto.UUID.generate(), else: token), delivered])
      if n == 103, do: query("DELETE FROM oban_jobs WHERE id=$1", [linked])
      if n == 106, do: query("UPDATE media_files SET revision=2 WHERE id=$1", [file])
      {file, token, linked, n}
    end
  end

  defp verify(:inspection, expected) do
    [[nil]] = query("SELECT to_regclass('media_inspection_events')").rows
    for {file, token, linked, n} <- expected do
      [[state, job_id]] = query("SELECT state,job_id FROM media_inspections WHERE media_file_id=$1", [file]).rows
      cond do
        n == 104 -> true = state == "failed"
        n == 105 -> true = state == "succeeded"
        n == 106 -> true = is_nil(job_id)
        n in [102, 103] -> true = job_id == linked
        true ->
          [[%{"media_file_id" => ^file, "token" => ^token}, 3, "media_inspections"]] = query("SELECT args,max_attempts,queue FROM oban_jobs WHERE id=$1", [job_id]).rows
      end
    end
    [[count]] = query("SELECT count(*) FROM media_files").rows
    true = count == length(expected)
  end

  defp file(type, n) do
    [[library]] = query("INSERT INTO libraries (name,path,content_type,inserted_at,updated_at) VALUES ('Synthetic', $1,$2,now(),now()) RETURNING id", ["/synthetic/#{type}/#{n}", type]).rows
    [[file]] = query("INSERT INTO media_files (library_id,relative_path,size_bytes,modified_at,availability,revision,last_seen_generation) VALUES ($1,'synthetic.bin',10,now(),'available',1,$2::text::uuid) RETURNING id", [library, Ecto.UUID.generate()]).rows
    file
  end

  defp job(worker, queue, args) do
    [[id]] = query("INSERT INTO oban_jobs (worker,queue,args,max_attempts) VALUES ($1,$2,$3,3) RETURNING id", ["Bolognesa." <> worker, queue, args]).rows
    id
  end

  defp query(sql, params \\ []), do: Ecto.Adapters.SQL.query!(CheckRepo, sql, params, log: false)
end

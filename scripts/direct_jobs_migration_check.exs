defmodule Bolognesa.DirectJobsMigrationCheckRepo do
  use Ecto.Repo, otp_app: :bolognesa, adapter: Ecto.Adapters.Postgres
end

defmodule Bolognesa.DirectJobsMigrationCheck do
  @moduledoc false
  alias Bolognesa.DirectJobsMigrationCheckRepo, as: CheckRepo

  @versions %{
    inspection: 20_261_017_120_000,
    music: 20_261_017_130_000,
    video: 20_261_017_140_000
  }

  @spec run(:inspection | :music | :video) :: :ok
  def run(kind) do
    if Mix.env() != :test or Process.whereis(Bolognesa.Repo),
      do: raise("Run with MIX_ENV=test mix run --no-start")

    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    config = [
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      database: "bolognesa_direct_jobs_migration_check",
      pool_size: 2,
      log: false
    ]

    Application.put_env(:bolognesa, CheckRepo, config)

    migrations =
      for file <-
            Path.wildcard(Application.app_dir(:bolognesa, "priv/repo/migrations/*.exs"))
            |> Enum.sort() do
        {version, _} = Integer.parse(Path.basename(file))
        [{module, _}] = Code.compile_file(file)
        {version, module}
      end

    version = Map.fetch!(@versions, kind)

    for scenario <- [:empty, :seeded, :mismatched] do
      Ecto.Adapters.Postgres.storage_down(config)
      :ok = Ecto.Adapters.Postgres.storage_up(config)
      {:ok, pid} = CheckRepo.start_link()

      try do
        Ecto.Migrator.run(CheckRepo, migrations, :up, to: version - 1, log: false)

        if scenario != :empty do
          query(
            "INSERT INTO accounts_users(name,email,role,hashed_password,locale,inserted_at,updated_at) VALUES ('Synthetic','synthetic@example.com','admin','synthetic-hash','en',now(),now())"
          )
        end

        expected = if scenario == :empty, do: [], else: seed(kind)
        before = stable_snapshot()

        if scenario == :mismatched do
          {_file, _token, linked, _n} =
            Enum.find(expected, fn {_file, _token, job, _n} -> not is_nil(job) end)

          query("UPDATE oban_jobs SET worker='Bolognesa.WrongWorker' WHERE id=$1", [linked])
          jobs = query("SELECT * FROM oban_jobs ORDER BY id").rows

          try do
            Ecto.Migrator.run(CheckRepo, migrations, :up, to: version, log: false)
            raise "Inconsistent job linkage unexpectedly accepted"
          rescue
            error in Postgrex.Error ->
              true = String.contains?(error.postgres.message, "mismatched")
          end

          ^jobs = query("SELECT * FROM oban_jobs ORDER BY id").rows
          ^before = stable_snapshot()

          for table <- legacy_tables(kind),
              do: [[true]] = query("SELECT to_regclass($1) IS NOT NULL", [table]).rows

          IO.puts(
            "#{kind} jobs migration: mismatched linkage aborts and rolls back earlier batches"
          )
        else
          Ecto.Migrator.run(CheckRepo, migrations, :up, to: version, log: false)
          ^before = stable_snapshot()
          verify(kind, expected)

          try do
            Ecto.Migrator.run(CheckRepo, migrations, :down, step: 1, log: false)
            raise "Reverse migration unexpectedly succeeded"
          rescue
            error in Ecto.MigrationError -> true = String.contains?(error.message, "irreversible")
          end

          IO.puts("#{kind} jobs migration: #{scenario} upgrade and refused reversal passed")
        end
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

      linked =
        if n in [102, 103],
          do:
            job("Libraries.Infrastructure.Jobs.InspectionWorker", "media_inspections", %{
              "media_file_id" => file,
              "token" => token
            }),
          else: nil

      query(
        "INSERT INTO media_inspections (media_file_id, token, observed_revision, state, job_id, inserted_at, updated_at) VALUES ($1,$2::text::uuid,1,$3,$4,now(),now())",
        [file, token, state, linked]
      )

      query(
        "INSERT INTO media_inspection_events (media_file_id,token,delivered_at,inserted_at,updated_at) VALUES ($1,$2::text::uuid,CASE WHEN $3 THEN now() END,now(),now())",
        [file, if(n == 106, do: Ecto.UUID.generate(), else: token), delivered]
      )

      if n == 103, do: query("DELETE FROM oban_jobs WHERE id=$1", [linked])
      if n == 106, do: query("UPDATE media_files SET revision=2 WHERE id=$1", [file])
      {file, token, linked, n}
    end
  end

  defp seed(:music) do
    for n <- 1..110 do
      file = file("music", n)
      token = Ecto.UUID.generate()
      tracks = if n == 106, do: %{"items" => []}, else: %{"items" => [%{"kind" => "audio"}]}

      query(
        "INSERT INTO media_inspections(media_file_id,token,observed_revision,state,tracks,inserted_at,updated_at) VALUES ($1,$2::text::uuid,1,'succeeded',$3,now(),now())",
        [file, token, tracks]
      )

      linked =
        if n in [101, 102, 103, 108, 109],
          do:
            job("Music.Infrastructure.Jobs.RefreshWorker", "music_imports", %{
              "file_id" => file,
              "revision" => 1
            }),
          else: nil

      delivered = not is_nil(linked)

      query(
        "INSERT INTO music_refresh_events(media_file_id,revision,inspection_token,job_id,delivered_at,inserted_at,updated_at) VALUES ($1,1,$2::text::uuid,$3,CASE WHEN $4 THEN now() END,now(),now())",
        [file, if(n == 105, do: Ecto.UUID.generate(), else: token), linked, delivered]
      )

      if n == 102, do: query("UPDATE oban_jobs SET state='discarded' WHERE id=$1", [linked])
      if n == 103, do: query("DELETE FROM oban_jobs WHERE id=$1", [linked])

      if n == 108,
        do:
          query("UPDATE oban_jobs SET state='executing',attempted_at=now() WHERE id=$1", [linked])

      if n == 109, do: query("UPDATE oban_jobs SET state='scheduled' WHERE id=$1", [linked])

      if n in [104, 107, 110] do
        query(
          "INSERT INTO music_imports(media_file_id,observed_revision,inspection_token,state,inserted_at,updated_at) VALUES ($1,1,$2::text::uuid,$3,now(),now())",
          [
            file,
            if(n == 110, do: Ecto.UUID.generate(), else: token),
            if(n == 107, do: "succeeded", else: "failed")
          ]
        )
      end

      if n == 107 do
        [[artist]] =
          query(
            "INSERT INTO music_artists(library_id,name,normalized_name,inserted_at,updated_at) SELECT library_id,'Synthetic','synthetic',now(),now() FROM media_files WHERE id=$1 RETURNING id",
            [file]
          ).rows

        [[album]] =
          query(
            "INSERT INTO music_albums(library_id,source_parent,title,normalized_title,artist_id,inserted_at,updated_at) SELECT library_id,decode('00','hex'),'Synthetic','synthetic',$1,now(),now() FROM media_files WHERE id=$2 RETURNING id",
            [artist, file]
          ).rows

        query(
          "INSERT INTO music_tracks(media_file_id,library_id,title,artist_id,album_id,observed_revision,inspection_token,inserted_at,updated_at) SELECT id,library_id,'Synthetic',$1,$2,1,$3::text::uuid,now(),now() FROM media_files WHERE id=$4",
          [artist, album, token, file]
        )
      end

      {file, token, linked, n}
    end
  end

  defp verify(:inspection, expected) do
    [[nil]] = query("SELECT to_regclass('media_inspection_events')").rows

    for {file, token, linked, n} <- expected do
      [[state, job_id]] =
        query("SELECT state,job_id FROM media_inspections WHERE media_file_id=$1", [file]).rows

      cond do
        n == 104 ->
          true = state == "failed"

        n == 105 ->
          true = state == "succeeded"

        n == 106 ->
          true = is_nil(job_id)

        n in [102, 103] ->
          true = job_id == linked

        true ->
          [[%{"media_file_id" => ^file, "token" => ^token}, 3, "media_inspections"]] =
            query("SELECT args,max_attempts,queue FROM oban_jobs WHERE id=$1", [job_id]).rows
      end
    end

    [[count]] = query("SELECT count(*) FROM media_files").rows
    true = count == length(expected)
  end

  defp verify(:music, expected) do
    [[nil]] = query("SELECT to_regclass('music_refresh_events')").rows

    for {file, token, linked, n} <- expected do
      rows =
        query(
          "SELECT state,inspection_token::text,job_id,failure_reason FROM music_imports WHERE media_file_id=$1",
          [file]
        ).rows

      case n do
        n when n in [105, 106] ->
          [] = rows

        _ ->
          [[state, ^token, job_id, reason]] = rows

          expected_state =
            cond do
              n in [102, 103, 104] -> "failed"
              n == 107 -> "succeeded"
              n == 108 -> "running"
              true -> "pending"
            end

          true = state == expected_state
          if linked, do: true = job_id == linked
          if n == 102, do: true = reason == "attempts_exhausted"
          if state == "pending", do: true = is_integer(job_id)
      end
    end

    [[count]] = query("SELECT count(*) FROM media_files").rows
    true = count == length(expected)
  end

  defp file(type, n) do
    [[library]] =
      query(
        "INSERT INTO libraries (name,path,content_type,inserted_at,updated_at) VALUES ('Synthetic', $1,$2,now(),now()) RETURNING id",
        ["/synthetic/#{type}/#{n}", type]
      ).rows

    [[file]] =
      query(
        "INSERT INTO media_files (library_id,relative_path,size_bytes,modified_at,availability,revision,last_seen_generation) VALUES ($1,'synthetic.bin',10,now(),'available',1,$2::text::uuid) RETURNING id",
        [library, Ecto.UUID.generate()]
      ).rows

    file
  end

  defp job(worker, queue, args) do
    [[id]] =
      query(
        "INSERT INTO oban_jobs (worker,queue,args,max_attempts) VALUES ($1,$2,$3,3) RETURNING id",
        ["Bolognesa." <> worker, queue, args]
      ).rows

    id
  end

  defp legacy_tables(:inspection), do: ["media_inspection_events"]
  defp legacy_tables(:music), do: ["music_refresh_events"]
  defp legacy_tables(:video), do: ["movie_identification_events", "series_identification_events"]

  defp stable_snapshot do
    for table <-
          ~w(accounts_users accounts_sessions libraries media_files movies series seasons episodes series_identification_episodes music_artists music_albums music_tracks),
        do: {table, query("SELECT * FROM #{table} ORDER BY id").rows}
  end

  defp query(sql, params \\ []), do: Ecto.Adapters.SQL.query!(CheckRepo, sql, params, log: false)
end

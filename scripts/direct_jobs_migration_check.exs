defmodule Bolognesa.DirectJobsMigrationCheckRepo do
  use Ecto.Repo, otp_app: :bolognesa, adapter: Ecto.Adapters.Postgres
end

defmodule Bolognesa.DirectJobsMigrationNoMatchProvider do
  @moduledoc false
  @spec search(String.t(), integer() | nil) :: {:ok, []}
  def search(_title, _year), do: {:ok, []}
end

defmodule Bolognesa.DirectJobsMigrationNotifier do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  @impl true
  def notify(_id), do: :ok
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

    Logger.configure(level: :warning)
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

    scenarios =
      [:empty, :seeded, :mismatched, :orphan_mismatched] ++
        if(kind == :music, do: [:current_mismatched, :current_revision], else: [])

    for scenario <- scenarios do
      Ecto.Adapters.Postgres.storage_down(config)
      :ok = Ecto.Adapters.Postgres.storage_up(config)
      {:ok, pid} = CheckRepo.start_link()

      try do
        migrate_previous(kind, scenario, migrations, version)

        if scenario != :empty do
          query(
            "INSERT INTO accounts_users(name,email,role,hashed_password,locale,inserted_at,updated_at) VALUES ('Synthetic','synthetic@example.com','admin','synthetic-hash','en',now(),now())"
          )
        end

        expected = if scenario == :empty, do: [], else: seed(kind)
        before = stable_snapshot()

        if scenario not in [:empty, :seeded] do
          {file, token, linked, _n} =
            Enum.find(expected, fn {_file, _token, job, _n} -> not is_nil(job) end)

          if scenario != :current_revision do
            query("UPDATE oban_jobs SET worker='Bolognesa.WrongWorker' WHERE id=$1", [linked])
          end

          if kind == :music and scenario != :mismatched do
            query(
              "INSERT INTO music_imports(media_file_id,observed_revision,inspection_token,state,job_id,inserted_at,updated_at) VALUES ($1,$2,$3::text::uuid,'pending',$4,now(),now())",
              [file, if(scenario == :current_revision, do: 2, else: 1), token, linked]
            )
          end

          if scenario == :orphan_mismatched do
            [table | _] = legacy_tables(kind)
            query("DELETE FROM #{table} WHERE media_file_id=$1", [file])
          end

          jobs = query("SELECT * FROM oban_jobs ORDER BY id").rows

          try do
            Ecto.Migrator.run(CheckRepo, migrations, :up, to: version, log: false)
            raise "Inconsistent job linkage unexpectedly accepted"
          rescue
            error in Postgrex.Error ->
              true =
                String.contains?(error.postgres.message, "mismatched") or
                  String.contains?(error.postgres.message, "inconsistent")
          end

          ^jobs = query("SELECT * FROM oban_jobs ORDER BY id").rows
          ^before = stable_snapshot()

          for table <- legacy_tables(kind),
              do: [[true]] = query("SELECT to_regclass($1) IS NOT NULL", [table]).rows

          IO.puts("#{kind} jobs migration: #{scenario} aborts and rolls back earlier batches")
        else
          Ecto.Migrator.run(CheckRepo, migrations, :up, to: version, log: false)
          ^before = stable_snapshot()
          verify(kind, expected)
          exercise(kind, expected)

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

  defp migrate_previous(:video, scenario, migrations, version) when scenario != :empty do
    Ecto.Migrator.run(CheckRepo, migrations, :up,
      to: Map.fetch!(@versions, :inspection) - 1,
      log: false
    )

    inspections = seed(:inspection)
    imports = seed(:music)
    before = stable_snapshot()
    Ecto.Migrator.run(CheckRepo, migrations, :up, to: version - 1, log: false)
    ^before = stable_snapshot()
    verify(:inspection, inspections)
    verify(:music, imports)
    IO.puts("Combined original-schema backlog preserved through inspection and Music upgrades")
  end

  defp migrate_previous(_kind, _scenario, migrations, version),
    do: Ecto.Migrator.run(CheckRepo, migrations, :up, to: version - 1, log: false)

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
    for n <- 1..111 do
      file = file("music", n)
      token = Ecto.UUID.generate()
      tracks = if n == 106, do: %{"items" => []}, else: %{"items" => [%{"kind" => "audio"}]}

      query(
        "INSERT INTO media_inspections(media_file_id,token,observed_revision,state,tracks,inserted_at,updated_at) VALUES ($1,$2::text::uuid,1,'succeeded',$3,now(),now())",
        [file, token, tracks]
      )

      linked =
        if n in [101, 102, 103, 108, 109, 111],
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

      linked =
        if n == 111 do
          query("UPDATE oban_jobs SET state='discarded' WHERE id=$1", [linked])

          retry_job =
            job("Music.Infrastructure.Jobs.RefreshWorker", "music_imports", %{
              "file_id" => file,
              "revision" => 1
            })

          query(
            "INSERT INTO music_imports(media_file_id,observed_revision,inspection_token,state,job_id,inserted_at,updated_at) VALUES ($1,1,$2::text::uuid,'pending',$3,now(),now())",
            [file, token, retry_job]
          )

          retry_job
        else
          linked
        end

      {file, token, linked, n}
    end
  end

  defp seed(:video) do
    for {type, owner, offset} <- [{"movie", "Movies", 0}, {"series", "Series", 1000}],
        n <- 1..108 do
      file = file(type, n)
      token = Ecto.UUID.generate()

      state =
        cond do
          n == 105 -> "manual_unidentified"
          n == 107 -> "failed"
          true -> "pending"
        end

      origin = if n == 105, do: "manual", else: "automatic"

      linked =
        if n in [102, 103],
          do:
            job("#{owner}.Infrastructure.Jobs.IdentificationWorker", "identifications", %{
              "file_id" => file,
              "token" => token
            }),
          else: nil

      query(
        "INSERT INTO #{type}_identifications(media_file_id,token,observed_revision,state,origin,job_id,inserted_at,updated_at) VALUES ($1,$2::text::uuid,1,$3,$4,$5,now(),now())",
        [file, token, state, origin, linked]
      )

      query(
        "INSERT INTO #{type}_identification_events(media_file_id,token,delivered_at,inserted_at,updated_at) VALUES ($1,$2::text::uuid,CASE WHEN $3 THEN now() END,now(),now())",
        [file, if(n == 106, do: Ecto.UUID.generate(), else: token), n in [102, 103, 104]]
      )

      if n == 103, do: query("DELETE FROM oban_jobs WHERE id=$1", [linked])
      if n == 106, do: query("UPDATE media_files SET revision=2 WHERE id=$1", [file])

      if n == 108,
        do:
          query(
            "UPDATE libraries SET content_type='music' WHERE id=(SELECT library_id FROM media_files WHERE id=$1)",
            [file]
          )

      if n == 105, do: confirm_manual(type, file)
      {file, token, linked, n + offset}
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

    [[count]] =
      query("SELECT count(*) FROM media_files WHERE id=ANY($1)", [
        Enum.map(expected, &elem(&1, 0))
      ]).rows

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

    [[count]] =
      query("SELECT count(*) FROM media_files WHERE id=ANY($1)", [
        Enum.map(expected, &elem(&1, 0))
      ]).rows

    true = count == length(expected)
  end

  defp verify(:video, expected) do
    for table <- legacy_tables(:video),
        do: [[nil]] = query("SELECT to_regclass($1)", [table]).rows

    for {file, token, linked, number} <- expected do
      {type, n} = if number > 1000, do: {"series", number - 1000}, else: {"movie", number}

      [[state, ^token, job_id]] =
        query(
          "SELECT state,token::text,job_id FROM #{type}_identifications WHERE media_file_id=$1",
          [file]
        ).rows

      cond do
        n == 104 ->
          true = state == "failed"

        n == 105 ->
          true = state == "manual"

        n in [106, 108] ->
          true = is_nil(job_id)

        n == 107 ->
          true = state == "failed"

        n in [102, 103] ->
          true = job_id == linked

        true ->
          [[%{"file_id" => ^file, "token" => ^token}, "identifications", 3]] =
            query("SELECT args,queue,max_attempts FROM oban_jobs WHERE id=$1", [job_id]).rows
      end
    end

    [[count]] =
      query("SELECT count(*) FROM media_files WHERE id=ANY($1)", [
        Enum.map(expected, &elem(&1, 0))
      ]).rows

    true = count == length(expected)
  end

  defp confirm_manual("movie", file) do
    [[movie]] =
      query(
        "INSERT INTO movies(provider,provider_id,title,inserted_at,updated_at) VALUES ('tmdb',42,'Synthetic movie',now(),now()) RETURNING id"
      ).rows

    query("UPDATE movie_identifications SET state='manual',movie_id=$1 WHERE media_file_id=$2", [
      movie,
      file
    ])
  end

  defp confirm_manual("series", file) do
    [[series]] =
      query(
        "INSERT INTO series(provider,provider_id,title,inserted_at,updated_at) VALUES ('tmdb',42,'Synthetic series',now(),now()) RETURNING id"
      ).rows

    [[season]] =
      query(
        "INSERT INTO seasons(provider,provider_id,series_id,number,title,inserted_at,updated_at) VALUES ('tmdb',43,$1,1,'Synthetic season',now(),now()) RETURNING id",
        [series]
      ).rows

    query("UPDATE series_identifications SET state='manual' WHERE media_file_id=$1", [file])

    for n <- 1..2 do
      [[episode]] =
        query(
          "INSERT INTO episodes(provider,provider_id,season_id,number,title,inserted_at,updated_at) VALUES ('tmdb',$1,$2,$3,'Synthetic episode',now(),now()) RETURNING id",
          [43 + n, season, n]
        ).rows

      query(
        "INSERT INTO series_identification_episodes(identification_id,episode_id,position) SELECT id,$1,$2 FROM series_identifications WHERE media_file_id=$3",
        [episode, n, file]
      )
    end

    query("UPDATE series_identifications SET state='manual' WHERE media_file_id=$1", [file])
  end

  defp exercise(_kind, []), do: :ok

  defp exercise(kind, expected) do
    previous = Bolognesa.Repo.put_dynamic_repo(CheckRepo)

    try do
      exercise_workers(kind, expected)
    after
      Bolognesa.Repo.put_dynamic_repo(previous)
    end
  end

  defp exercise_workers(:inspection, [{file, _, _, _}, {lost, _, _, _} | _]) do
    job = migrated_job("media_inspections", file)

    :ok =
      Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker.perform(
        job,
        Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository,
        Bolognesa.Libraries.Support.SuccessfulMediaProbe,
        Bolognesa.DirectJobsMigrationNotifier
      )

    [["succeeded"]] =
      query("SELECT state FROM media_inspections WHERE media_file_id=$1", [file]).rows

    query(
      "DELETE FROM oban_jobs WHERE id=(SELECT job_id FROM media_inspections WHERE media_file_id=$1)",
      [lost]
    )

    %{error: nil} =
      Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository.reconcile_jobs(
        DateTime.utc_now()
      )

    [["failed"]] =
      query("SELECT state FROM media_inspections WHERE media_file_id=$1", [lost]).rows
  end

  defp exercise_workers(:music, [{file, _, _, _}, {lost, _, _, _} | _]) do
    :ok =
      Bolognesa.Music.Infrastructure.Jobs.RefreshWorker.perform(
        migrated_job("music_imports", file)
      )

    [["succeeded"]] = query("SELECT state FROM music_imports WHERE media_file_id=$1", [file]).rows

    query(
      "DELETE FROM oban_jobs WHERE id=(SELECT job_id FROM music_imports WHERE media_file_id=$1)",
      [lost]
    )

    :ok =
      Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository.reconcile_jobs(
        DateTime.utc_now()
      )

    [["failed"]] = query("SELECT state FROM music_imports WHERE media_file_id=$1", [lost]).rows
  end

  defp exercise_workers(:video, expected) do
    for {file, _, _, n} <- expected, n in [1, 1001] do
      {table, worker, repository} =
        if n == 1 do
          {"movie_identifications", Bolognesa.Movies.Infrastructure.Jobs.IdentificationWorker,
           Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository}
        else
          {"series_identifications", Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker,
           Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository}
        end

      :ok =
        worker.perform(
          migrated_job(table, file),
          repository,
          Bolognesa.DirectJobsMigrationNoMatchProvider
        )

      [[state]] = query("SELECT state FROM #{table} WHERE media_file_id=$1", [file]).rows
      true = state != "pending"
      {lost, _, _, _} = Enum.find(expected, fn {_, _, _, number} -> number == n + 1 end)

      query(
        "DELETE FROM oban_jobs WHERE id=(SELECT job_id FROM #{table} WHERE media_file_id=$1)",
        [lost]
      )

      :ok = repository.reconcile_jobs(DateTime.utc_now())
      [["failed"]] = query("SELECT state FROM #{table} WHERE media_file_id=$1", [lost]).rows
    end
  end

  defp migrated_job(table, file) do
    [[id]] = query("SELECT job_id FROM #{table} WHERE media_file_id=$1", [file]).rows
    %{Bolognesa.Repo.get!(Oban.Job, id) | attempt: 1}
  end

  defp file(type, n) do
    [[library]] =
      query(
        "INSERT INTO libraries (name,path,content_type,inserted_at,updated_at) VALUES ('Synthetic', $1,$2,now(),now()) RETURNING id",
        ["/synthetic/#{type}/#{n}/#{System.unique_integer([:positive])}", type]
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
    stable =
      for table <-
            ~w(accounts_users accounts_sessions libraries media_files movies series seasons episodes series_identification_episodes music_artists music_albums music_tracks),
          do: {table, query("SELECT * FROM #{table} ORDER BY id").rows}

    manual =
      for table <- ~w(movie_identifications series_identifications),
          do: {table, query("SELECT * FROM #{table} WHERE origin='manual' ORDER BY id").rows}

    stable ++ manual
  end

  defp query(sql, params \\ []), do: Ecto.Adapters.SQL.query!(CheckRepo, sql, params, log: false)
end

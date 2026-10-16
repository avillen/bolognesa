defmodule Bolognesa.Series.IdentifySeriesFileTest do
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Series.Application.UseCases.IdentifySeriesFile
  alias Bolognesa.Series.Domain.ValueObjects.EpisodeSelection
  alias Bolognesa.Series.Infrastructure.Jobs.IdentificationWorker
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository
  alias Bolognesa.Test.SyntheticSeriesProvider, as: Provider
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  use Bolognesa.DataCase, async: false

  test "begin without a job id preserves the outbox link" do
    {file, token} = pending("Serie S01E01.mkv")

    Repo.update_all(from(row in SeriesIdentificationSchema, where: row.media_file_id == ^file.id),
      set: [job_id: 7]
    )

    assert {:ok, _} = Repository.begin_identification(file.id, token, nil)
    assert {:ok, %{job_id: 7, started_at: %DateTime{}}} = Repository.get(file.id)
  end

  test "an old token cannot create catalog identities after a retry" do
    {file, token} = pending("Serie S01E01.mkv")
    assert {:ok, fresh} = Repository.retry(file.id)
    {:ok, series} = Provider.details(201)
    {:ok, season} = Provider.season(201, 1)
    {:ok, selection} = EpisodeSelection.new(series, season, [1])

    count =
      Repo.aggregate(SeriesSchema, :count) + Repo.aggregate(SeasonSchema, :count) +
        Repo.aggregate(EpisodeSchema, :count)

    assert {:ok, :stale} = Repository.complete_series(file.id, token, [], selection, nil)
    assert {:ok, ^fresh} = Repository.get(file.id)

    assert Repo.aggregate(SeriesSchema, :count) + Repo.aggregate(SeasonSchema, :count) +
             Repo.aggregate(EpisodeSchema, :count) == count
  end

  @tag committed: true
  test "a rejected second entry rolls back catalog decision and the first entry" do
    Sandbox.unboxed_run(Repo, fn ->
      {file, token} = pending("Serie S00E01E02.mkv")

      catalog_count =
        Repo.aggregate(SeriesSchema, :count) + Repo.aggregate(SeasonSchema, :count) +
          Repo.aggregate(EpisodeSchema, :count)

      entry_count = Repo.aggregate(SeriesIdentificationEpisodeSchema, :count)

      SQL.query!(Repo, """
      ALTER TABLE series_identification_episodes ADD CONSTRAINT identification_refactor_reject_second
      CHECK (position <> 2) NOT VALID
      """)

      try do
        assert {:error, :unavailable} =
                 IdentifySeriesFile.call(file.id, token, 1, Repository, Provider)

        assert {:ok, %{state: :pending, token: ^token, episode_ids: []}} =
                 Repository.get(file.id)

        assert Repo.aggregate(SeriesSchema, :count) + Repo.aggregate(SeasonSchema, :count) +
                 Repo.aggregate(EpisodeSchema, :count) == catalog_count

        assert Repo.aggregate(SeriesIdentificationEpisodeSchema, :count) == entry_count
      after
        SQL.query!(
          Repo,
          "ALTER TABLE series_identification_episodes DROP CONSTRAINT identification_refactor_reject_second"
        )

        Repo.delete!(Repo.get!(MediaFileSchema, file.id))
        Repo.delete!(Repo.get!(LibrarySchema, file.library_id))
      end
    end)
  end

  test "identifies a special double file atomically and repeats harmlessly" do
    {file, token} = pending("Serie S00E01E02.mkv")
    assert :ok = IdentifySeriesFile.call(file.id, token, 1, Repository, Provider)

    assert {:ok, %{state: :automatic, episode_ids: ids, needs_review?: false}} =
             Repository.get(file.id)

    assert length(ids) == 2
    assert :ok = IdentifySeriesFile.call(file.id, token, 2, Repository, Provider)
    assert {:ok, %{episode_ids: ^ids}} = Repository.get(file.id)
    assert {:ok, request} = Repository.retry(file.id)
    assert request.episode_ids == []

    assert {:ok, :stale} =
             Repository.complete_series(file.id, token, [], nil, :incomplete_episodes)
  end

  test "incomplete ambiguous and unusable selections never confirm a subset" do
    for {name, reason} <- [
          {"Serie S01E01E99.mkv", "incomplete_episodes"},
          {"Ambigua S01E01.mkv", "ambiguous_series"},
          {"Serie 123.mkv", "unusable_name"}
        ] do
      {file, token} = pending(name)
      assert :ok = IdentifySeriesFile.call(file.id, token, 1, Repository, Provider)

      assert {:ok,
              %{
                state: :unmatched,
                episode_ids: [],
                failure_reason: ^reason,
                needs_review?: true
              }} = Repository.get(file.id)
    end
  end

  test "transient provider errors retry then become visible and worker dispatches by source" do
    {file, token} = pending("Unavailable S01E01.mkv")

    assert {:error, :provider_unavailable} =
             IdentifySeriesFile.call(file.id, token, 1, Repository, Provider)

    assert :ok = IdentifySeriesFile.call(file.id, token, 3, Repository, Provider)

    assert {:ok, %{state: :failed, failure_reason: "provider_unavailable"}} =
             Repository.get(file.id)

    {file, token} = pending("Serie 1x01-02.mkv")
    job = %Oban.Job{args: %{"file_id" => file.id, "token" => token}, attempt: 1}
    assert :ok = IdentificationWorker.perform(job, Repository, Provider)
    assert {:ok, %{episode_ids: [_, _]}} = Repository.get(file.id)
  end

  defp pending(name) do
    library =
      Repo.insert!(%LibrarySchema{
        name: "Series",
        path: "/synthetic/#{Ecto.UUID.generate()}",
        content_type: :series
      })

    file =
      Repo.insert!(%MediaFileSchema{
        library_id: library.id,
        relative_path: name,
        size_bytes: 8,
        modified_at: DateTime.utc_now(),
        availability: :available,
        revision: 1,
        last_seen_generation: Ecto.UUID.generate()
      })

    token = Ecto.UUID.generate()

    Repo.insert!(%SeriesIdentificationSchema{
      media_file_id: file.id,
      observed_revision: 1,
      state: :pending,
      token: token
    })

    {file, token}
  end
end

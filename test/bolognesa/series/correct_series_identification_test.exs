defmodule Bolognesa.Series.CorrectSeriesIdentificationTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeasonSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesSchema
  alias Bolognesa.Movies.Application.UseCases.CorrectMovieIdentification
  alias Bolognesa.Series
  alias Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification
  alias Bolognesa.Series.Application.UseCases.FetchSeriesSeason
  alias Bolognesa.Series.Application.UseCases.IdentifySeriesFile
  alias Bolognesa.Series.Application.UseCases.SearchSeriesCandidates
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository
  alias Bolognesa.Test.BlockingSeriesProvider
  alias Bolognesa.Test.SyntheticSeriesProvider
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @actor %AuthenticatedUser{id: 1, role: :admin}

  test "corrects a complete set protects manual choices and rejects invalid or foreign types" do
    {file, _token} = pending(:series)
    choice = {:tmdb, 201, 0, [1, 2]}
    assert {:error, :forbidden} = correct(nil, file.id, choice)
    assert {:ok, decision} = correct(@actor, file.id, choice)
    assert length(decision.episode_ids) == 2
    assert {:error, :manual_locked} = Repository.retry(file.id)
    assert {:error, :invalid_selection} = correct(@actor, file.id, {:tmdb, 201, 0, [1, 1]})
    assert {:error, :incomplete_episodes} = correct(@actor, file.id, {:tmdb, 201, 0, [1, 99]})
    assert {:ok, %{episode_ids: ids}} = Repository.get(file.id)
    assert ids == decision.episode_ids

    assert {:ok, %{state: :manual_unidentified, episode_ids: []}} =
             correct(@actor, file.id, :unidentified)

    assert Repo.all(EpisodeSchema) == []
    assert Repo.all(SeasonSchema) == []
    assert Repo.all(SeriesSchema) == []
    assert Repo.all(SeriesSchema) == []
    assert Repo.all(SeasonSchema) == []
    assert Repo.all(EpisodeSchema) == []

    {movie_file, _} = pending(:movie)
    assert {:error, :wrong_content_type} = correct(@actor, movie_file.id, choice)

    assert {:error, :wrong_content_type} =
             CorrectMovieIdentification.call(
               @actor,
               file.id,
               :unidentified,
               Repository,
               SyntheticSeriesProvider
             )
  end

  test "shrinking a multiple episode selection preserves the remaining episode and hierarchy" do
    {file, _} = pending(:series)
    assert {:ok, original} = correct(@actor, file.id, {:tmdb, 201, 1, [1, 2]})
    [first_id, second_id] = original.episode_ids

    assert {:ok, %{episode_ids: [^second_id]}} =
             correct(@actor, file.id, {:tmdb, 201, 1, [2]})

    refute Repo.get(EpisodeSchema, first_id)
    refute Repo.get(EpisodeSchema, first_id)
    assert Repo.get(EpisodeSchema, second_id)
    assert length(Repo.all(SeasonSchema)) == 1
    assert length(Repo.all(SeriesSchema)) == 1
  end

  test "moving to another season removes the empty season and preserves the series" do
    {file, _} = pending(:series)
    assert {:ok, original} = correct(@actor, file.id, {:tmdb, 201, 0, [1]})
    [id] = original.episode_ids
    season = Repo.get!(SeasonSchema, Repo.get!(EpisodeSchema, id).season_id)

    assert {:ok, _} = correct(@actor, file.id, {:tmdb, 201, 1, [2]})

    refute Repo.get(EpisodeSchema, id)
    refute Repo.get(SeasonSchema, season.id)
    refute Repo.get(SeasonSchema, season.id)
    assert Repo.get(SeriesSchema, season.series_id)
    assert length(Repo.all(SeasonSchema)) == 1
  end

  test "another missing version preserves the episode season and series" do
    {first, _} = pending(:series)
    {second, _} = pending(:series)
    choice = {:tmdb, 201, 1, [1]}
    assert {:ok, original} = correct(@actor, first.id, choice)
    [id] = original.episode_ids
    assert {:ok, %{episode_ids: [^id]}} = correct(@actor, first.id, choice)
    assert {:ok, %{episode_ids: [^id]}} = correct(@actor, second.id, choice)
    second |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()

    assert {:ok, _} = correct(@actor, first.id, :unidentified)
    episode = Repo.get!(EpisodeSchema, id)
    season = Repo.get!(SeasonSchema, episode.season_id)
    assert Repo.get(SeriesSchema, season.series_id)
    assert Repo.get(EpisodeSchema, id)
    assert Repo.get(SeasonSchema, season.id)
    assert Repo.get(SeriesSchema, season.series_id)
  end

  test "reassignment to another series removes the old hierarchy and preserves the new one" do
    {file, _} = pending(:series)
    assert {:ok, original} = correct(@actor, file.id, {:tmdb, 201, 1, [1, 2]})
    [first_id, second_id] = original.episode_ids
    season = Repo.get!(SeasonSchema, Repo.get!(EpisodeSchema, first_id).season_id)

    assert {:ok, replacement} = correct(@actor, file.id, {:tmdb, 202, 1, [1]})
    [new_id] = replacement.episode_ids

    refute Repo.get(EpisodeSchema, first_id)
    refute Repo.get(EpisodeSchema, second_id)
    refute Repo.get(SeasonSchema, season.id)
    refute Repo.get(SeriesSchema, season.series_id)
    episode = Repo.get!(EpisodeSchema, new_id)
    new_season = Repo.get!(SeasonSchema, episode.season_id)
    assert Repo.get(SeriesSchema, new_season.series_id)
  end

  test "manual set survives an older automatic completion" do
    Sandbox.mode(Repo, {:shared, self()})
    supervisor = start_supervised!(Task.Supervisor)
    {file, token} = pending(:series)
    owner = self()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Process.put(:series_test_owner, owner)
        IdentifySeriesFile.call(file.id, token, 1, Repository, BlockingSeriesProvider)
      end)

    assert_receive {:series_waiting, worker}, 2000
    assert {:ok, corrected} = correct(@actor, file.id, {:tmdb, 201, 1, [2]})
    send(worker, :continue)
    assert :ok = Task.await(task)
    assert {:ok, %{episode_ids: ids, token: current_token}} = Repository.get(file.id)
    assert ids == corrected.episode_ids
    assert current_token == corrected.token
  end

  test "file revision changing during manual provider lookup rejects the stale result" do
    Sandbox.mode(Repo, {:shared, self()})
    supervisor = start_supervised!(Task.Supervisor)
    {file, _} = pending(:series)
    owner = self()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Process.put(:series_test_owner, owner)

        CorrectSeriesIdentification.call(
          @actor,
          file.id,
          {:tmdb, 201, 1, [1]},
          Repository,
          BlockingSeriesProvider
        )
      end)

    assert_receive {:series_waiting, worker}, 2000
    file |> Ecto.Changeset.change(revision: 2) |> Repo.update!()
    send(worker, :continue)
    assert {:error, :source_changed} = Task.await(task)
    assert {:ok, %{episode_ids: []}} = Repository.get(file.id)
  end

  test "manual lookup APIs authorize and bound their input" do
    assert {:error, :forbidden} = Series.search_candidates(nil, "Serie")
    assert {:error, :forbidden} = Series.fetch_series_season(nil, 201, 0)

    assert {:error, :invalid_query} =
             SearchSeriesCandidates.call(
               @actor,
               String.duplicate("x", 257),
               SyntheticSeriesProvider
             )

    assert {:ok, [_]} = SearchSeriesCandidates.call(@actor, " Serie ", SyntheticSeriesProvider)

    assert {:error, :invalid_selection} =
             FetchSeriesSeason.call(@actor, 201, -1, SyntheticSeriesProvider)

    assert :not_found = FetchSeriesSeason.call(@actor, 404, 1, SyntheticSeriesProvider)

    assert {:error, :provider_unavailable} =
             FetchSeriesSeason.call(@actor, 503, 1, SyntheticSeriesProvider)

    assert {:ok, %{number: 0}} = FetchSeriesSeason.call(@actor, 201, 0, SyntheticSeriesProvider)
  end

  @tag committed: true
  test "a rejected correction preserves the prior set and rolls back all replacement hierarchy" do
    Sandbox.unboxed_run(Repo, fn ->
      {file, _token} = pending(:series)
      assert {:ok, original} = correct(@actor, file.id, {:tmdb, 201, 1, [1]})

      SQL.query!(
        Repo,
        "ALTER TABLE series_identification_episodes ADD CONSTRAINT series_test_reject_second CHECK (position <> 2) NOT VALID"
      )

      try do
        assert {:error, :unavailable} = correct(@actor, file.id, {:tmdb, 202, 1, [1, 2]})
        assert {:ok, ^original} = Repository.get(file.id)
        assert Repo.get_by(SeriesSchema, provider_id: 202) == nil
        assert Repo.get_by(SeasonSchema, provider_id: 2021) == nil
        assert Repo.get_by(EpisodeSchema, provider_id: 20_211) == nil
        assert Repo.get_by(EpisodeSchema, provider_id: 20_212) == nil
      after
        SQL.query!(
          Repo,
          "ALTER TABLE series_identification_episodes DROP CONSTRAINT series_test_reject_second"
        )

        assert {:ok, _} = correct(@actor, file.id, :unidentified)
        Repo.delete!(Repo.get!(MediaFileSchema, file.id))
        Repo.delete!(Repo.get!(LibrarySchema, file.library_id))
      end
    end)
  end

  defp correct(actor, id, choice),
    do: CorrectSeriesIdentification.call(actor, id, choice, Repository, SyntheticSeriesProvider)

  defp pending(type) do
    library =
      Repo.insert!(%LibrarySchema{
        name: "Source",
        path: "/synthetic/#{Ecto.UUID.generate()}",
        content_type: type
      })

    file =
      Repo.insert!(%MediaFileSchema{
        library_id: library.id,
        relative_path: "Serie S01E01.mkv",
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

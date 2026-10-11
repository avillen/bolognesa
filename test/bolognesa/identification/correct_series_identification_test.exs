defmodule Bolognesa.Identification.CorrectSeriesIdentificationTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identification

  alias Bolognesa.Identification.Application.UseCases.{
    CorrectMovieIdentification,
    CorrectSeriesIdentification,
    GetSeriesSeason,
    IdentifySeriesFile,
    SearchSeriesCandidates
  }

  alias Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Identity.Domain.Entities.Actor

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    IdentificationSchema,
    LibrarySchema,
    MediaFileSchema,
    SeasonSchema,
    SeriesSchema
  }

  alias Bolognesa.Test.{BlockingSeriesProvider, SyntheticSeriesProvider}
  alias Ecto.Adapters.SQL.Sandbox
  @actor %Actor{id: 1, role: :admin}

  test "corrects a complete set protects manual choices and rejects invalid or foreign types" do
    {file, _token} = pending(:series)
    choice = {:tmdb, 201, 0, [1, 2]}
    assert {:error, :forbidden} = correct(nil, file.id, choice)
    assert {:ok, decision} = correct(@actor, file.id, choice)
    assert length(decision.catalog_entry_ids) == 2
    assert {:error, :manual_locked} = Repository.retry(file.id)
    assert {:error, :invalid_selection} = correct(@actor, file.id, {:tmdb, 201, 0, [1, 1]})
    assert {:error, :incomplete_episodes} = correct(@actor, file.id, {:tmdb, 201, 0, [1, 99]})
    assert {:ok, %{catalog_entry_ids: ids}} = Repository.get(file.id)
    assert ids == decision.catalog_entry_ids

    assert {:ok, %{state: :manual_unidentified, catalog_entry_ids: []}} =
             correct(@actor, file.id, :unidentified)

    assert Repo.all(EpisodeSchema) == []
    assert Repo.all(SeasonSchema) == []
    assert Repo.all(SeriesSchema) == []
    assert Repo.all(CatalogEntrySchema) == []

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
    [first_id, second_id] = original.catalog_entry_ids

    assert {:ok, %{catalog_entry_ids: [^second_id]}} =
             correct(@actor, file.id, {:tmdb, 201, 1, [2]})

    refute Repo.get(EpisodeSchema, first_id)
    refute Repo.get(CatalogEntrySchema, first_id)
    assert Repo.get(EpisodeSchema, second_id)
    assert length(Repo.all(SeasonSchema)) == 1
    assert length(Repo.all(SeriesSchema)) == 1
  end

  test "moving to another season removes the empty season and preserves the series" do
    {file, _} = pending(:series)
    assert {:ok, original} = correct(@actor, file.id, {:tmdb, 201, 0, [1]})
    [id] = original.catalog_entry_ids
    season = Repo.get!(SeasonSchema, Repo.get!(EpisodeSchema, id).season_id)

    assert {:ok, _} = correct(@actor, file.id, {:tmdb, 201, 1, [2]})

    refute Repo.get(EpisodeSchema, id)
    refute Repo.get(SeasonSchema, season.id)
    refute Repo.get(CatalogEntrySchema, season.id)
    assert Repo.get(SeriesSchema, season.series_id)
    assert length(Repo.all(SeasonSchema)) == 1
  end

  test "another missing version preserves the episode season and series" do
    {first, _} = pending(:series)
    {second, _} = pending(:series)
    choice = {:tmdb, 201, 1, [1]}
    assert {:ok, original} = correct(@actor, first.id, choice)
    [id] = original.catalog_entry_ids
    assert {:ok, %{catalog_entry_ids: [^id]}} = correct(@actor, first.id, choice)
    assert {:ok, %{catalog_entry_ids: [^id]}} = correct(@actor, second.id, choice)
    second |> Ecto.Changeset.change(availability: :missing) |> Repo.update!()

    assert {:ok, _} = correct(@actor, first.id, :unidentified)
    episode = Repo.get!(EpisodeSchema, id)
    season = Repo.get!(SeasonSchema, episode.season_id)
    assert Repo.get(SeriesSchema, season.series_id)
    assert Repo.get(CatalogEntrySchema, id)
    assert Repo.get(CatalogEntrySchema, season.id)
    assert Repo.get(CatalogEntrySchema, season.series_id)
  end

  test "reassignment to another series removes the old hierarchy and preserves the new one" do
    {file, _} = pending(:series)
    assert {:ok, original} = correct(@actor, file.id, {:tmdb, 201, 1, [1, 2]})
    [first_id, second_id] = original.catalog_entry_ids
    season = Repo.get!(SeasonSchema, Repo.get!(EpisodeSchema, first_id).season_id)

    assert {:ok, replacement} = correct(@actor, file.id, {:tmdb, 202, 1, [1]})
    [new_id] = replacement.catalog_entry_ids

    for id <- [first_id, second_id, season.id, season.series_id] do
      refute Repo.get(CatalogEntrySchema, id)
    end

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
    assert {:ok, %{catalog_entry_ids: ids, token: current_token}} = Repository.get(file.id)
    assert ids == corrected.catalog_entry_ids
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
    assert {:ok, %{catalog_entry_ids: []}} = Repository.get(file.id)
  end

  test "manual lookup APIs authorize and bound their input" do
    assert {:error, :forbidden} = Identification.search_series_candidates(nil, "Serie")
    assert {:error, :forbidden} = Identification.series_season(nil, 201, 0)

    assert {:error, :invalid_query} =
             SearchSeriesCandidates.call(
               @actor,
               String.duplicate("x", 257),
               SyntheticSeriesProvider
             )

    assert {:ok, [_]} = SearchSeriesCandidates.call(@actor, " Serie ", SyntheticSeriesProvider)

    assert {:error, :invalid_selection} =
             GetSeriesSeason.call(@actor, 201, -1, SyntheticSeriesProvider)

    assert {:ok, %{number: 0}} = GetSeriesSeason.call(@actor, 201, 0, SyntheticSeriesProvider)
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

    Repo.insert!(%IdentificationSchema{
      media_file_id: file.id,
      observed_revision: 1,
      state: :pending,
      token: token
    })

    {file, token}
  end
end

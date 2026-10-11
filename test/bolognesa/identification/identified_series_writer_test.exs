defmodule Bolognesa.Identification.IdentifiedSeriesWriterTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identification.Domain.{
    EpisodeDetails,
    EpisodeSelection,
    SeasonDetails,
    SeriesDetails
  }

  alias Bolognesa.Identification.Infrastructure.Repositories.IdentifiedSeriesWriter

  alias Bolognesa.Infrastructure.Persistence.{
    CatalogEntrySchema,
    EpisodeSchema,
    SeasonSchema,
    SeriesSchema
  }

  alias Ecto.Adapters.SQL.Sandbox

  test "reuses hierarchy and preserves metadata across versions" do
    selection = selection()
    assert {:ok, ids} = Repo.transaction(fn -> IdentifiedSeriesWriter.upsert!(selection) end)
    assert length(ids) == 2
    assert {:ok, ^ids} = Repo.transaction(fn -> IdentifiedSeriesWriter.upsert!(selection) end)
    changed = %{selection | series: %{selection.series | title: "Later metadata"}}
    assert {:ok, ^ids} = Repo.transaction(fn -> IdentifiedSeriesWriter.upsert!(changed) end)
    assert Repo.one!(SeriesSchema).title == "Serie"
    assert Repo.aggregate(SeriesSchema, :count) == 1
    assert Repo.aggregate(SeasonSchema, :count) == 1
    assert Repo.aggregate(EpisodeSchema, :count) == 2
    assert Repo.aggregate(CatalogEntrySchema, :count) == 4
    assert Enum.map(ids, &Repo.get!(EpisodeSchema, &1).number) == [1, 2]
  end

  test "failure reverses all hierarchy writes" do
    assert {:error, :synthetic_failure} =
             Repo.transaction(fn ->
               IdentifiedSeriesWriter.upsert!(selection())
               Repo.rollback(:synthetic_failure)
             end)

    assert Repo.aggregate(CatalogEntrySchema, :count) == 0
  end

  @tag committed: true
  test "concurrent selections reuse every identity" do
    supervisor = start_supervised!(Task.Supervisor)
    owner = self()

    try do
      tasks =
        for _ <- 1..2 do
          Task.Supervisor.async_nolink(supervisor, fn ->
            Sandbox.unboxed_run(Repo, fn ->
              send(owner, {:ready, self()})

              receive do
                :go -> Repo.transaction(fn -> IdentifiedSeriesWriter.upsert!(selection()) end)
              end
            end)
          end)
        end

      workers =
        for _ <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(workers, &send(&1, :go))
      assert [{:ok, first}, {:ok, second}] = Enum.map(tasks, &Task.await/1)
      assert first == second

      assert Sandbox.unboxed_run(Repo, fn ->
               Repo.aggregate(CatalogEntrySchema, :count)
             end) == 4
    after
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(EpisodeSchema)
        Repo.delete_all(SeasonSchema)
        Repo.delete_all(SeriesSchema)
        Repo.delete_all(from entry in CatalogEntrySchema, where: entry.kind != :movie)
      end)
    end
  end

  defp selection do
    series = %SeriesDetails{provider_id: 201, title: "Serie"}

    season = %SeasonDetails{
      provider_id: 301,
      series_provider_id: 201,
      number: 0,
      episodes: [
        %EpisodeDetails{provider_id: 401, season_number: 0, number: 1, title: "Uno"},
        %EpisodeDetails{provider_id: 402, season_number: 0, number: 2, title: "Dos"}
      ]
    }

    {:ok, selection} = EpisodeSelection.new(series, season, [1, 2])
    selection
  end
end

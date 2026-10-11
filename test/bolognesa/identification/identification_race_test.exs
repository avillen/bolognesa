defmodule Bolognesa.Identification.IdentificationRaceTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Identification.Application.{CorrectIdentification, IdentifyMediaFile}
  alias Bolognesa.Identification.Domain.{MovieCandidate, MovieDetails}
  alias Bolognesa.Infrastructure.Persistence.CatalogEntrySchema

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias CatalogEntrySchema
  alias Ecto.Adapters.SQL.Sandbox

  defmodule BlockedProvider do
    def search(_title, _year) do
      send(Process.get(:owner), {:search_waiting, self()})

      receive do
        :continue -> {:ok, [%MovieCandidate{provider_id: 71, title: "Old result"}]}
      end
    end

    def details(71), do: {:ok, %MovieDetails{provider_id: 71, title: "Old result"}}
  end

  defmodule CorrectionProvider do
    def details(72), do: {:ok, %MovieDetails{provider_id: 72, title: "Manual result"}}
  end

  test "stale movie completion does not create a catalog identity" do
    {file, token} = fixture()
    assert {:ok, fresh} = Repository.retry(file.id)
    count = Repo.aggregate(CatalogEntrySchema, :count)
    details = %MovieDetails{provider_id: 9183, title: "Old result"}

    assert {:ok, :stale} = Repository.complete(file.id, token, [], details, false)
    assert {:ok, ^fresh} = Repository.get(file.id)
    assert Repo.aggregate(CatalogEntrySchema, :count) == count
  end

  test "manual movie and manual unidentified survive an in-flight result" do
    Sandbox.mode(Repo, {:shared, self()})
    supervisor = start_supervised!(Task.Supervisor)

    for choice <- [{:tmdb, 72}, :unidentified] do
      {file, token} = fixture()
      owner = self()

      task =
        Task.Supervisor.async_nolink(supervisor, fn ->
          Process.put(:owner, owner)
          IdentifyMediaFile.call(file.id, token, 1, Repository, BlockedProvider)
        end)

      assert_receive {:search_waiting, worker}, 2_000

      assert {:ok, corrected} =
               CorrectIdentification.call(
                 %Actor{id: 1, role: :admin},
                 file.id,
                 choice,
                 Repository,
                 CorrectionProvider
               )

      send(worker, :continue)
      assert :ok = Task.await(task)

      assert {:ok, %{origin: :manual, catalog_entry_ids: catalog_entry_ids, token: current_token}} =
               Repository.get(file.id)

      assert catalog_entry_ids == corrected.catalog_entry_ids
      assert current_token == corrected.token
    end
  end

  @tag committed: true
  test "concurrent versions reuse one TMDb movie" do
    Sandbox.unboxed_run(Repo, fn ->
      {first, _} = fixture()
      {second, _} = fixture()
      supervisor = start_supervised!(Task.Supervisor)
      details = %MovieDetails{provider_id: 9182, title: "Shared movie"}

      try do
        tasks =
          for file <- [first, second] do
            Task.Supervisor.async_nolink(supervisor, fn ->
              Sandbox.unboxed_run(Repo, fn ->
                Repository.correct(file.id, details)
              end)
            end)
          end

        assert [
                 {:ok, %{catalog_entry_ids: [first_catalog_entry_id]}},
                 {:ok, %{catalog_entry_ids: [second_catalog_entry_id]}}
               ] =
                 Enum.map(tasks, &Task.await/1)

        assert first_catalog_entry_id == second_catalog_entry_id

        assert Repo.aggregate(
                 from(movie in MovieSchema,
                   join: entry in CatalogEntrySchema,
                   on: entry.id == movie.id,
                   where: entry.provider_id == 9182
                 ),
                 :count,
                 :id
               ) == 1
      after
        Repo.delete_all(from file in MediaFileSchema, where: file.id in ^[first.id, second.id])

        Repo.delete_all(
          from movie in MovieSchema,
            where:
              movie.id in subquery(
                from entry in CatalogEntrySchema,
                  where: entry.provider_id == 9182,
                  select: entry.id
              )
        )

        Repo.delete_all(from entry in CatalogEntrySchema, where: entry.provider_id == 9182)

        Repo.delete_all(
          from library in LibrarySchema,
            where: library.id in ^[first.library_id, second.library_id]
        )
      end
    end)
  end

  defp fixture do
    library =
      Repo.insert!(
        LibrarySchema.changeset(%LibrarySchema{}, %{
          name: "Race",
          path: "/race-#{System.unique_integer([:positive])}"
        })
      )

    file =
      Repo.insert!(
        MediaFileSchema.changeset(%MediaFileSchema{}, %{
          library_id: library.id,
          relative_path: "Film.mkv",
          size_bytes: 1,
          modified_at: DateTime.utc_now(),
          last_seen_generation: Ecto.UUID.generate()
        })
      )

    token = Ecto.UUID.generate()

    Repo.insert!(
      IdentificationSchema.changeset(%IdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: token,
        state: :pending
      })
    )

    {file, token}
  end
end

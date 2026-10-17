defmodule Bolognesa.Movies.IdentificationRaceTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.LibrarySchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Infrastructure.Persistence.MovieSchema
  alias Bolognesa.Movies.Application.UseCases.CorrectMovieIdentification
  alias Bolognesa.Movies.Application.UseCases.IdentifyMovieFile
  alias Bolognesa.Movies.Domain.ValueObjects.MovieCandidate
  alias Bolognesa.Movies.Domain.ValueObjects.MovieDetails
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository, as: Repository
  alias Ecto.Adapters.SQL
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

  defmodule RevisionProvider do
    def details(id) do
      send(Process.get(:owner), {:details_waiting, self()})

      receive do
        :continue -> {:ok, %MovieDetails{provider_id: id, title: "Changed during lookup"}}
      end
    end
  end

  test "a revision change during manual lookup cannot create a movie or choice" do
    Sandbox.mode(Repo, {:shared, self()})
    supervisor = start_supervised!(Task.Supervisor)
    {file, _} = fixture()
    owner = self()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Process.put(:owner, owner)

        CorrectMovieIdentification.call(
          %AuthenticatedUser{id: 1, role: :admin},
          file.id,
          {:tmdb, 9184},
          Repository,
          RevisionProvider
        )
      end)

    assert_receive {:details_waiting, worker}, 2_000
    Repo.update!(Ecto.Changeset.change(file, revision: 2))
    send(worker, :continue)
    assert {:error, :source_changed} = Task.await(task)
    assert Repo.get_by(MovieSchema, provider_id: 9184) == nil
    assert {:ok, %{state: :pending}} = Repository.get(file.id)
  end

  test "a revision change during automatic lookup cannot create a movie" do
    Sandbox.mode(Repo, {:shared, self()})
    supervisor = start_supervised!(Task.Supervisor)
    {file, token} = fixture()
    owner = self()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Process.put(:owner, owner)
        IdentifyMovieFile.call(file.id, token, 1, Repository, BlockedProvider)
      end)

    assert_receive {:search_waiting, worker}, 2_000
    Repo.update!(Ecto.Changeset.change(file, revision: 2))
    send(worker, :continue)
    assert :ok = Task.await(task)
    assert Repo.get_by(MovieSchema, provider_id: 71) == nil
    assert {:ok, %{state: :pending}} = Repository.get(file.id)
  end

  test "stale movie completion does not create a catalog identity" do
    {file, token} = fixture()
    assert {:ok, fresh} = Repository.retry(file.id)
    count = Repo.aggregate(MovieSchema, :count)
    details = %MovieDetails{provider_id: 9183, title: "Old result"}

    assert {:ok, :stale} = Repository.complete(file.id, token, [], details, false)
    assert {:ok, ^fresh} = Repository.get(file.id)
    assert Repo.aggregate(MovieSchema, :count) == count
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
          IdentifyMovieFile.call(file.id, token, 1, Repository, BlockedProvider)
        end)

      assert_receive {:search_waiting, worker}, 2_000

      assert {:ok, corrected} =
               CorrectMovieIdentification.call(
                 %AuthenticatedUser{id: 1, role: :admin},
                 file.id,
                 choice,
                 Repository,
                 CorrectionProvider
               )

      send(worker, :continue)
      assert :ok = Task.await(task)

      assert {:ok, %{origin: :manual, movie_id: movie_id, token: current_token}} =
               Repository.get(file.id)

      assert movie_id == corrected.movie_id
      assert current_token == corrected.token
    end
  end

  @tag committed: true
  test "a rejected movie choice rolls back its new work and preserves the pending decision" do
    Sandbox.unboxed_run(Repo, fn ->
      {file, token} = fixture()

      SQL.query!(
        Repo,
        "ALTER TABLE movie_identifications ADD CONSTRAINT movie_test_reject_choice CHECK (media_file_id <> #{file.id} OR movie_id IS NULL) NOT VALID"
      )

      try do
        assert {:error, :unavailable} =
                 Repository.complete(
                   file.id,
                   token,
                   [],
                   %MovieDetails{provider_id: 9185, title: "Rejected"},
                   false
                 )

        assert Repo.get_by(MovieSchema, provider_id: 9185) == nil
        assert {:ok, %{state: :pending, token: ^token, movie_id: nil}} = Repository.get(file.id)
      after
        SQL.query!(
          Repo,
          "ALTER TABLE movie_identifications DROP CONSTRAINT movie_test_reject_choice"
        )

        Repo.delete!(Repo.get!(MediaFileSchema, file.id))
        Repo.delete!(Repo.get!(LibrarySchema, file.library_id))
      end
    end)
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
                Repository.correct(file.id, file.revision, details)
              end)
            end)
          end

        assert [
                 {:ok, %{movie_id: first_movie_id}},
                 {:ok, %{movie_id: second_movie_id}}
               ] =
                 Enum.map(tasks, &Task.await/1)

        assert first_movie_id == second_movie_id

        assert Repo.aggregate(
                 from(movie in MovieSchema,
                   where: movie.provider_id == 9182
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
                from movie in MovieSchema,
                  where: movie.provider_id == 9182,
                  select: movie.id
              )
        )

        Repo.delete_all(from entry in MovieSchema, where: entry.provider_id == 9182)

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
      MovieIdentificationSchema.changeset(%MovieIdentificationSchema{}, %{
        media_file_id: file.id,
        observed_revision: 1,
        token: token,
        state: :pending
      })
    )

    {file, token}
  end
end

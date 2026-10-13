defmodule Bolognesa.Music.ImportConcurrencyTest do
  use Bolognesa.DataCase, async: false
  import Bolognesa.MusicFixtures
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, LibrarySchema, MediaFileSchema}

  alias Bolognesa.Infrastructure.Persistence.{
    MusicAlbumSchema,
    MusicArtistSchema,
    MusicImportSchema,
    MusicTrackSchema
  }

  alias Bolognesa.Music
  alias Ecto.Adapters.SQL.Sandbox

  test "competing imports share one local album and artist" do
    supervisor = start_supervised!(Task.Supervisor)

    Sandbox.unboxed_run(Repo, fn ->
      first = music_fixture(tags: %{"album" => "Sample", "artist" => "Ensemble"})

      second =
        music_fixture(
          tags: %{"album" => "Sample", "artist" => "Ensemble"},
          relative_path: "album/second.mp3"
        )

      Repo.update!(change(second.file, library_id: first.library.id))
      ids = [first.file.id, second.file.id]
      parent = self()

      try do
        tasks =
          for id <- ids do
            Task.Supervisor.async_nolink(supervisor, fn ->
              Sandbox.unboxed_run(Repo, fn ->
                send(parent, {:ready, self()})

                receive do
                  :import -> Music.refresh_track(id, 1)
                end
              end)
            end)
          end

        for _ <- tasks, do: assert_receive({:ready, _}, 1000)
        for task <- tasks, do: send(task.pid, :import)
        for task <- tasks, do: assert(:ok == Task.await(task))

        assert Repo.aggregate(
                 from(a in MusicAlbumSchema, where: a.library_id == ^first.library.id),
                 :count
               ) == 1

        assert Repo.aggregate(
                 from(a in MusicArtistSchema, where: a.library_id == ^first.library.id),
                 :count
               ) == 1
      after
        Repo.delete_all(from(r in MusicTrackSchema, where: r.media_file_id in ^ids))
        Repo.delete_all(from(r in MusicImportSchema, where: r.media_file_id in ^ids))
        Repo.delete_all(from(r in MusicAlbumSchema, where: r.library_id == ^first.library.id))
        Repo.delete_all(from(r in MusicArtistSchema, where: r.library_id == ^first.library.id))
        Repo.delete_all(from(r in InspectionSchema, where: r.media_file_id in ^ids))
        Repo.delete_all(from(r in MediaFileSchema, where: r.id in ^ids))
        Repo.delete!(first.library)
        Repo.delete!(second.library)
      end

      assert Repo.get(LibrarySchema, first.library.id) == nil
      assert Repo.get(LibrarySchema, second.library.id) == nil
    end)
  end
end

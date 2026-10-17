defmodule Bolognesa.Music.MusicJourneyTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Persistence.{InspectionSchema, MediaFileSchema}
  alias Bolognesa.Libraries
  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker

  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository

  alias Bolognesa.Libraries.Support.SuccessfulMusicProbe
  alias Bolognesa.Music
  alias Bolognesa.Playback
  alias Bolognesa.Playback.Domain.ReadModels.Source

  test "scan and durable inspection produce a playable stable local track" do
    root = Application.fetch_env!(:bolognesa, :library_roots) |> hd()
    path = Path.join(root, "music-journey-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    File.write!(Path.join(path, "sample.mp3"), "controlled audio")
    actor = %AuthenticatedUser{id: 1, role: :admin}

    {:ok, library} =
      Libraries.create_library(actor, %{name: "Sample music", path: path, content_type: :music})

    assert {:ok, _scan} = Libraries.start_scan(actor, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    file = Repo.one!(MediaFileSchema)
    inspection = Repo.get_by!(InspectionSchema, media_file_id: file.id)
    job = Repo.get!(Oban.Job, inspection.job_id)

    assert :ok =
             InspectionWorker.perform(
               %{job | attempt: 1},
               EctoInspectionRepository,
               SuccessfulMusicProbe
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :music_imports)
    assert {:ok, %{items: [track]}} = Music.list_tracks(actor, "Sample", 1, library.id)

    assert {:ok, %Source{relative_path: "sample.mp3"}} =
             Playback.start_track(actor, track.id, track.file_id)

    assert {:ok, _scan} = Libraries.start_scan(actor, library.id)
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :library_scans)
    assert {:ok, %{items: [again]}} = Music.list_tracks(actor, "Sample", 1, library.id)
    assert again.id == track.id
    assert File.read!(Path.join(path, "sample.mp3")) == "controlled audio"
  end
end

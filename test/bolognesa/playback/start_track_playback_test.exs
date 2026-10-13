defmodule Bolognesa.Playback.StartTrackPlaybackTest do
  use Bolognesa.DataCase, async: true
  import Bolognesa.MusicFixtures
  alias Bolognesa.Playback
  alias Bolognesa.Playback.Domain.ReadModels.Source

  test "authorized tracks require the matching current audio source" do
    first = refresh_fixture()
    second = refresh_fixture()
    assert {:ok, %Source{}} = Playback.start_track(first.actor, first.track.id, first.file.id)
    assert {:error, :forbidden} = Playback.start_track(nil, first.track.id, first.file.id)

    assert {:error, :not_found} =
             Playback.start_track(first.actor, first.track.id, second.file.id)

    Repo.update!(change(first.inspection, token: Ecto.UUID.generate()))
    assert {:error, :not_found} = Playback.start_track(first.actor, first.track.id, first.file.id)
  end
end

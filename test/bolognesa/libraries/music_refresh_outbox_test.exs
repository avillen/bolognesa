defmodule Bolognesa.Libraries.MusicRefreshOutboxTest do
  use Bolognesa.DataCase, async: true
  use Oban.Testing, repo: Bolognesa.Repo
  import Bolognesa.MusicFixtures
  alias Bolognesa.Infrastructure.Persistence.MusicRefreshEventSchema
  alias Bolognesa.Libraries.Domain.ValueObjects.Inspection.{MusicTags, TechnicalMedia}

  alias Bolognesa.Libraries.Infrastructure.Repositories.{
    EctoInspectionRepository,
    EctoMusicRefreshOutboxRepository
  }

  test "only accepted music inspections create minimal durable refresh jobs" do
    fixture = music_fixture(inspection_state: :running)

    {:ok, media} =
      TechnicalMedia.new(%{
        format: "mp3",
        tracks: [%{kind: :audio, codec: "mp3"}],
        music_tags: MusicTags.from_raw(%{"title" => "Sample"})
      })

    assert {:ok, :stale} =
             EctoInspectionRepository.complete_inspection(
               fixture.file.id,
               Ecto.UUID.generate(),
               media
             )

    assert Repo.all(MusicRefreshEventSchema) == []

    assert :ok =
             EctoInspectionRepository.complete_inspection(
               fixture.file.id,
               fixture.inspection.token,
               media
             )

    assert :ok !=
             EctoInspectionRepository.complete_inspection(
               fixture.file.id,
               fixture.inspection.token,
               media
             )

    assert {:ok, 1} = EctoMusicRefreshOutboxRepository.dispatch_batch(100)
    assert [%Oban.Job{args: args}] = all_enqueued(queue: "music_imports")
    assert args == %{"file_id" => fixture.file.id, "revision" => fixture.file.revision}
    assert {:ok, 0} = EctoMusicRefreshOutboxRepository.dispatch_batch(100)
  end
end

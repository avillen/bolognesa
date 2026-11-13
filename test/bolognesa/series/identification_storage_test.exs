defmodule Bolognesa.Series.IdentificationStorageTest do
  alias Bolognesa.SeriesFixtures
  alias Ecto.Changeset
  alias Ecto.UUID
  use Bolognesa.DataCase, async: true

  alias Bolognesa.Series.Application.UseCases.CorrectSeriesIdentification
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository

  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository

  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema

  test "manual corrections persist a part and reject a part containing multiple episodes" do
    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Example S01E01-part2.mp4")
    decision = SeriesFixtures.identify(file, 1, [1])
    assert Map.fetch!(decision, :part_number) == 2
    row = Repo.get_by!(SeriesIdentificationSchema, media_file_id: file.id)
    assert Map.fetch!(row, :part_number) == 2

    assert {:error, :manual_locked} =
             EctoIdentificationRepository.retry(file.id)

    assert {:error, :invalid_selection} =
             CorrectSeriesIdentification.call(
               %Bolognesa.Accounts.Domain.Entities.AuthenticatedUser{id: 1, role: :admin},
               file.id,
               {:tmdb, 201, 1, [1, 2]},
               EctoIdentificationRepository,
               Bolognesa.Test.SyntheticSeriesProvider
             )

    assert Repo.get_by!(SeriesIdentificationSchema, media_file_id: file.id).part_number == 2

    file |> Changeset.change(revision: 2) |> Repo.update!()

    assert {:ok, 0} =
             Repo.transaction(fn ->
               EctoIdentificationRepository.request_batch!(
                 Repo,
                 [
                   %{file_id: file.id, revision: 2, requested?: true}
                 ]
               )
             end)

    assert {:ok, ^decision} = EctoIdentificationRepository.get(file.id)
  end

  test "associations require confirmed decisions unique episodes and positive unique positions" do
    library = SeriesFixtures.library()
    file = SeriesFixtures.file(library.id, "Serie S01E01.mkv")
    decision = SeriesFixtures.identify(file, 1, [1, 2])
    [first, second] = decision.episode_ids
    row = Repo.get_by!(SeriesIdentificationSchema, media_file_id: file.id)
    assert Repo.get!(EpisodeSchema, first).season_id == Repo.get!(EpisodeSchema, second).season_id

    assert {:error, _} =
             Repo.insert(
               SeriesIdentificationEpisodeSchema.changeset(
                 %SeriesIdentificationEpisodeSchema{},
                 %{identification_id: row.id, episode_id: first, position: 3}
               )
             )

    assert {:error, _} =
             Repo.insert(
               SeriesIdentificationEpisodeSchema.changeset(
                 %SeriesIdentificationEpisodeSchema{},
                 %{identification_id: row.id, episode_id: second, position: 0}
               )
             )

    file2 = SeriesFixtures.file(library.id, "Pending.mkv")

    attrs = %{
      media_file_id: file2.id,
      observed_revision: 1,
      token: UUID.generate(),
      state: :pending
    }

    pending =
      Repo.insert!(SeriesIdentificationSchema.changeset(%SeriesIdentificationSchema{}, attrs))

    assert {:error, invalid} =
             Repo.insert(
               SeriesIdentificationEpisodeSchema.changeset(
                 %SeriesIdentificationEpisodeSchema{},
                 %{identification_id: pending.id, episode_id: first, position: 1}
               )
             )

    assert Keyword.has_key?(invalid.errors, :identification_id)

    assert {:error, _} =
             Repo.insert(
               SeriesIdentificationSchema.changeset(%SeriesIdentificationSchema{}, attrs)
             )
  end
end

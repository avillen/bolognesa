defmodule Bolognesa.Identification.IdentifySeriesFileTest do
  use Bolognesa.DataCase, async: false
  alias Bolognesa.Identification.Application.IdentifySeriesFile
  alias Bolognesa.Identification.Infrastructure.Jobs.IdentificationWorker

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Infrastructure.Persistence.{
    IdentificationSchema,
    LibrarySchema,
    MediaFileSchema
  }

  alias Bolognesa.Test.SyntheticSeriesProvider, as: Provider

  test "identifies a special double file atomically and repeats harmlessly" do
    {file, token} = pending("Serie S00E01E02.mkv")
    assert :ok = IdentifySeriesFile.call(file.id, token, 1, Repository, Provider)

    assert {:ok, %{state: :automatic, catalog_entry_ids: ids, needs_review?: false}} =
             Repository.get(file.id)

    assert length(ids) == 2
    assert :ok = IdentifySeriesFile.call(file.id, token, 2, Repository, Provider)
    assert {:ok, %{catalog_entry_ids: ^ids}} = Repository.get(file.id)
    assert {:ok, request} = Repository.retry(file.id)
    assert request.catalog_entry_ids == []

    assert {:ok, :stale} =
             Repository.complete_series(file.id, token, [], nil, :incomplete_episodes)
  end

  test "incomplete ambiguous and unusable selections never confirm a subset" do
    for {name, reason} <- [
          {"Serie S01E01E99.mkv", "incomplete_episodes"},
          {"Ambigua S01E01.mkv", "ambiguous_series"},
          {"Serie 123.mkv", "unusable_name"}
        ] do
      {file, token} = pending(name)
      assert :ok = IdentifySeriesFile.call(file.id, token, 1, Repository, Provider)

      assert {:ok,
              %{
                state: :unmatched,
                catalog_entry_ids: [],
                failure_reason: ^reason,
                needs_review?: true
              }} = Repository.get(file.id)
    end
  end

  test "transient provider errors retry then become visible and worker dispatches by source" do
    {file, token} = pending("Unavailable S01E01.mkv")

    assert {:error, :provider_unavailable} =
             IdentifySeriesFile.call(file.id, token, 1, Repository, Provider)

    assert :ok = IdentifySeriesFile.call(file.id, token, 3, Repository, Provider)

    assert {:ok, %{state: :failed, failure_reason: "provider_unavailable"}} =
             Repository.get(file.id)

    {file, token} = pending("Serie 1x01-02.mkv")
    job = %Oban.Job{args: %{"file_id" => file.id, "token" => token}, attempt: 1}
    assert :ok = IdentificationWorker.perform(job, Repository, Provider, Provider)
    assert {:ok, %{catalog_entry_ids: [_, _]}} = Repository.get(file.id)
  end

  defp pending(name) do
    library =
      Repo.insert!(%LibrarySchema{
        name: "Series",
        path: "/synthetic/#{Ecto.UUID.generate()}",
        content_type: :series
      })

    file =
      Repo.insert!(%MediaFileSchema{
        library_id: library.id,
        relative_path: name,
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

defmodule Bolognesa.Identification.IdentificationRaceTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identification.Application.{CorrectIdentification, IdentifyMediaFile}
  alias Bolognesa.Identification.Domain.{MovieCandidate, MovieDetails}

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository,
    as: Repository

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

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

  test "manual movie and manual unidentified survive an in-flight result" do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
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

      assert {:ok, %{origin: :manual, movie_id: movie_id, token: current_token}} =
               Repository.get(file.id)

      assert movie_id == corrected.movie_id
      assert current_token == corrected.token
    end
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

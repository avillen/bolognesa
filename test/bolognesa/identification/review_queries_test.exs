defmodule Bolognesa.Identification.ReviewQueriesTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identification

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.IdentificationSchema

  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository.MediaFileSchema

  test "shows pending and failed files to administrators only" do
    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Review", path: "/review"}))

    for {name, state} <- [{"a.mkv", :pending}, {"b.mkv", :failed}] do
      file =
        Repo.insert!(
          MediaFileSchema.changeset(%MediaFileSchema{}, %{
            library_id: library.id,
            relative_path: name,
            size_bytes: 1,
            modified_at: DateTime.utc_now(),
            last_seen_generation: Ecto.UUID.generate()
          })
        )

      Repo.insert!(
        IdentificationSchema.changeset(%IdentificationSchema{}, %{
          media_file_id: file.id,
          observed_revision: 1,
          token: Ecto.UUID.generate(),
          state: state
        })
      )
    end

    assert {:error, :forbidden} = Identification.list_review_items(nil, 1)

    assert {:ok, %{items: items, total: 2}} =
             Identification.list_review_items(%Actor{id: 1, role: :admin}, 1)

    assert Enum.map(items, & &1.filename) == ["a.mkv", "b.mkv"]
  end
end

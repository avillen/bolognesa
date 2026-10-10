defmodule Bolognesa.Identification.ReviewQueriesTest do
  use Bolognesa.DataCase, async: false

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identification
  alias Bolognesa.Identification.Application.Dto.{ReviewItem, ReviewPage}
  alias Bolognesa.Identification.Domain.Identification, as: IdentificationDecision
  alias Bolognesa.Identification.Infrastructure.Persistence.EctoReviewReader
  alias Bolognesa.Libraries.Domain.MediaFile

  alias Bolognesa.Persistence.IdentificationSchema

  alias Bolognesa.Persistence.LibrarySchema
  alias Bolognesa.Persistence.MediaFileSchema

  test "shows pending, failed and manually unidentified files to administrators only" do
    library =
      Repo.insert!(LibrarySchema.changeset(%LibrarySchema{}, %{name: "Review", path: "/review"}))

    for {name, state} <- [
          {"a.mkv", :pending},
          {"b.mkv", :failed},
          {"c.mkv", :manual_unidentified}
        ] do
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
          state: state,
          origin: if(state == :manual_unidentified, do: :manual, else: nil)
        })
      )
    end

    assert {:error, :forbidden} = Identification.list_review_items(nil, 1)

    assert {:ok, %ReviewPage{items: [%ReviewItem{} | _] = items, total: 3}} =
             Identification.list_review_items(%Actor{id: 1, role: :admin}, 1)

    assert Enum.map(items, & &1.filename) == ["a.mkv", "b.mkv", "c.mkv"]

    assert {:ok, {[{%IdentificationDecision{}, %MediaFile{}, nil} | _], 3}} =
             EctoReviewReader.list_review_items(1)
  end
end

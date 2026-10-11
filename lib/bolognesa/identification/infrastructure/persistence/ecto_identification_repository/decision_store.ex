defmodule Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.DecisionStore do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Identification.Domain.Identification
  alias Bolognesa.Identification.Infrastructure.Persistence.IdentificationMapper
  alias Bolognesa.Infrastructure.Persistence.IdentificationSchema

  @type repo :: atom()

  @spec get(repo(), pos_integer()) :: IdentificationSchema.t() | nil
  def get(repo, file_id),
    do: repo.get_by(IdentificationSchema, [media_file_id: file_id], log: false)

  @spec lock(repo(), pos_integer()) :: IdentificationSchema.t() | nil
  def lock(repo, file_id) do
    repo.one(
      from(row in IdentificationSchema, where: row.media_file_id == ^file_id, lock: "FOR UPDATE"),
      log: false
    )
  end

  @spec save!(repo(), IdentificationSchema.t() | nil, Identification.t()) ::
          IdentificationSchema.t()
  def save!(repo, row, decision) do
    row = row || %IdentificationSchema{}

    row
    |> IdentificationSchema.changeset(IdentificationMapper.to_attributes(decision))
    |> repo.insert_or_update!(log: false)
  end
end

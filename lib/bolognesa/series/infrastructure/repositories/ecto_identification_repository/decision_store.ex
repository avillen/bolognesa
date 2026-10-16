defmodule Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Series.Domain.Entities.Identification
  alias Bolognesa.Series.Infrastructure.Repositories.IdentificationMapper

  @type repo :: atom()

  @spec get(repo(), pos_integer()) :: SeriesIdentificationSchema.t() | nil
  def get(repo, file_id),
    do: repo.get_by(SeriesIdentificationSchema, [media_file_id: file_id], log: false)

  @spec lock(repo(), pos_integer()) :: SeriesIdentificationSchema.t() | nil
  def lock(repo, file_id) do
    repo.one(
      from(row in SeriesIdentificationSchema,
        where: row.media_file_id == ^file_id,
        lock: "FOR UPDATE"
      ),
      log: false
    )
  end

  @spec save!(repo(), SeriesIdentificationSchema.t() | nil, Identification.t()) ::
          SeriesIdentificationSchema.t()
  def save!(repo, row, decision) do
    row = row || %SeriesIdentificationSchema{}

    row
    |> SeriesIdentificationSchema.changeset(IdentificationMapper.to_attributes(decision))
    |> repo.insert_or_update!(log: false)
  end
end

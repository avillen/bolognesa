defmodule Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.MovieIdentificationSchema
  alias Bolognesa.Movies.Domain.Entities.Identification
  alias Bolognesa.Movies.Infrastructure.Repositories.IdentificationMapper

  @type repo :: atom()

  @spec get(repo(), pos_integer()) :: MovieIdentificationSchema.t() | nil
  def get(repo, file_id),
    do: repo.get_by(MovieIdentificationSchema, [media_file_id: file_id], log: false)

  @spec lock(repo(), pos_integer()) :: MovieIdentificationSchema.t() | nil
  def lock(repo, file_id) do
    repo.one(
      from(row in MovieIdentificationSchema,
        where: row.media_file_id == ^file_id,
        lock: "FOR UPDATE"
      ),
      log: false
    )
  end

  @spec save!(repo(), MovieIdentificationSchema.t() | nil, Identification.t()) ::
          MovieIdentificationSchema.t()
  def save!(repo, row, decision) do
    row = row || %MovieIdentificationSchema{}

    row
    |> MovieIdentificationSchema.changeset(IdentificationMapper.to_attributes(decision))
    |> repo.insert_or_update!(log: false)
  end
end

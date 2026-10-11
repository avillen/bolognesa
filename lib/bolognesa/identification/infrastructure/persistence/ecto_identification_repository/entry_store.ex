defmodule Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.EntryStore do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Identification.Infrastructure.Persistence.EctoIdentificationRepository.DecisionStore
  alias Bolognesa.Infrastructure.Persistence.IdentificationEntrySchema

  @spec ids(DecisionStore.repo(), pos_integer()) :: [pos_integer()]
  def ids(repo, identification_id) do
    repo.all(
      from(row in IdentificationEntrySchema,
        where: row.identification_id == ^identification_id,
        order_by: row.position,
        select: row.catalog_entry_id
      ),
      log: false
    )
  end

  @spec replace!(DecisionStore.repo(), pos_integer(), [pos_integer()]) :: :ok
  def replace!(repo, identification_id, ids) do
    repo.delete_all(
      from(row in IdentificationEntrySchema, where: row.identification_id == ^identification_id),
      log: false
    )

    ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, position} ->
      repo.insert!(
        %IdentificationEntrySchema{
          identification_id: identification_id,
          catalog_entry_id: id,
          position: position
        },
        log: false
      )
    end)
  end
end

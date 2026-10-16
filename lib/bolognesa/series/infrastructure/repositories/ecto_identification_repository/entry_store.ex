defmodule Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.EntryStore do
  @moduledoc false
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Series.Infrastructure.Repositories.EctoIdentificationRepository.DecisionStore

  @spec ids(DecisionStore.repo(), pos_integer()) :: [pos_integer()]
  def ids(repo, identification_id) do
    repo.all(
      from(row in SeriesIdentificationEpisodeSchema,
        where: row.identification_id == ^identification_id,
        order_by: row.position,
        select: row.episode_id
      ),
      log: false
    )
  end

  @spec replace!(DecisionStore.repo(), pos_integer(), [pos_integer()]) :: :ok
  def replace!(repo, identification_id, ids) do
    repo.delete_all(
      from(row in SeriesIdentificationEpisodeSchema,
        where: row.identification_id == ^identification_id
      ),
      log: false
    )

    ids
    |> Enum.with_index(1)
    |> Enum.each(fn {id, position} ->
      repo.insert!(
        %SeriesIdentificationEpisodeSchema{
          identification_id: identification_id,
          episode_id: id,
          position: position
        },
        log: false
      )
    end)
  end
end

defmodule Bolognesa.SeriesIdentificationFixtures do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema
  alias Bolognesa.Repo

  @spec insert_decision!(map(), [pos_integer()]) :: SeriesIdentificationSchema.t()
  def insert_decision!(attrs, ids) do
    Repo.transaction(fn ->
      row =
        Repo.insert!(SeriesIdentificationSchema.changeset(%SeriesIdentificationSchema{}, attrs))

      Enum.each(Enum.with_index(ids, 1), fn {id, position} ->
        Repo.insert!(%SeriesIdentificationEpisodeSchema{
          identification_id: row.id,
          episode_id: id,
          position: position
        })
      end)

      row
    end)
    |> then(fn {:ok, row} -> row end)
  end
end

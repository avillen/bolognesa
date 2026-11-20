defmodule Bolognesa.Series.Infrastructure.Readers.EpisodeEntries do
  alias Ecto.Query
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Series.Infrastructure.Readers.ConfirmedFiles

  @spec query() :: Query.t()
  def query do
    tagged =
      from [relation, decision] in ConfirmedFiles.query(),
        where: not is_nil(decision.part_number),
        select: relation.episode_id

    from episode in EpisodeSchema,
      left_join: file in ^ConfirmedFiles.rows(),
      on: file.episode_id == episode.id,
      where: not is_nil(file.part_number) or episode.id not in subquery(tagged),
      group_by: [episode.id, file.part_number],
      select: %{
        id: episode.id,
        number: episode.number,
        season_id: episode.season_id,
        part_number: file.part_number,
        version_count: count(file.file_id, :distinct),
        available_version_count:
          filter(count(file.file_id, :distinct), file.availability == :available)
      }
  end
end

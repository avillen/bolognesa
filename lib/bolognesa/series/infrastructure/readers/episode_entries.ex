defmodule Bolognesa.Series.Infrastructure.Readers.EpisodeEntries do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.EpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema

  @spec query() :: Ecto.Query.t()
  def query do
    tagged =
      from relation in SeriesIdentificationEpisodeSchema,
        join: decision in SeriesIdentificationSchema,
        on: decision.id == relation.identification_id,
        where: decision.state in [:automatic, :manual] and not is_nil(decision.part_number),
        select: relation.episode_id

    from episode in EpisodeSchema,
      left_join: relation in SeriesIdentificationEpisodeSchema,
      on: relation.episode_id == episode.id,
      left_join: decision in SeriesIdentificationSchema,
      on: decision.id == relation.identification_id and decision.state in [:automatic, :manual],
      left_join: file in MediaFileSchema,
      on: file.id == decision.media_file_id,
      where: not is_nil(decision.part_number) or episode.id not in subquery(tagged),
      group_by: [episode.id, decision.part_number],
      select: %{
        id: episode.id,
        number: episode.number,
        season_id: episode.season_id,
        part_number: decision.part_number,
        version_count: count(file.id, :distinct),
        available_version_count:
          filter(count(file.id, :distinct), file.availability == :available)
      }
  end
end

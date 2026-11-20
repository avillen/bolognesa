defmodule Bolognesa.Series.Infrastructure.Readers.ConfirmedFiles do
  @moduledoc false
  import Ecto.Query
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationEpisodeSchema
  alias Bolognesa.Infrastructure.Persistence.SeriesIdentificationSchema

  @doc "Episode relations whose automatic or manual decision confirms a file, bound as relation, decision, file."
  @spec query() :: Ecto.Query.t()
  def query do
    from relation in SeriesIdentificationEpisodeSchema,
      join: decision in SeriesIdentificationSchema,
      on: decision.id == relation.identification_id,
      join: file in MediaFileSchema,
      on: file.id == decision.media_file_id,
      where: decision.state in [:automatic, :manual]
  end

  @doc "The confirmed files as a subquery, for left joins."
  @spec rows() :: Ecto.Query.t()
  def rows do
    subquery(
      from [relation, decision, file] in query(),
        select: %{
          episode_id: relation.episode_id,
          part_number: decision.part_number,
          file_id: file.id,
          library_id: file.library_id,
          availability: file.availability
        }
    )
  end
end

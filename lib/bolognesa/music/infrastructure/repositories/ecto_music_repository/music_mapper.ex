defmodule Bolognesa.Music.Infrastructure.Repositories.EctoMusicRepository.MusicMapper do
  @moduledoc false
  alias Bolognesa.Infrastructure.Persistence.MusicTrackSchema
  alias Bolognesa.Music.Domain.Entities.Track
  @spec to_track(MusicTrackSchema.t()) :: Track.t()
  def to_track(row),
    do: struct!(Track, Map.take(Map.from_struct(row), Map.keys(Map.from_struct(%Track{}))))
end

defmodule Bolognesa.Music.Application.Ports.Repositories.MusicRepository do
  @moduledoc "Atomic, revalidated application of musical metadata."
  alias Bolognesa.Music.Domain.Entities.Track
  alias Bolognesa.Music.Domain.ValueObjects.{Observation, TrackMetadata}
  @type adapter :: atom()
  @type result :: {:ok, Track.t() | :stale} | {:error, :unavailable}
  @callback apply_observation(Observation.t(), TrackMetadata.t()) :: result()
end

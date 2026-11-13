defmodule Bolognesa.Music.Application.Ports.Repositories.MusicRepository do
  @moduledoc "Atomic, revalidated application of musical metadata."
  alias Bolognesa.Music.Domain.Entities.Track
  alias Bolognesa.Music.Domain.ValueObjects.CatalogMetadata
  alias Bolognesa.Music.Domain.ValueObjects.Observation
  @type adapter :: atom()
  @type result :: {:ok, Track.t() | :stale} | {:error, :unavailable}
  @callback apply_observation(Observation.t(), CatalogMetadata.t()) :: result()
end

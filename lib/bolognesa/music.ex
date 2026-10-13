defmodule Bolognesa.Music do
  @moduledoc "Local music identities, import and authorized listening reads."
  alias Bolognesa.Music.Application.UseCases.RefreshTrack
  alias Bolognesa.Music.Infrastructure.Readers.EctoObservationsReader
  alias Bolognesa.Music.Infrastructure.Repositories.EctoMusicRepository
  @spec refresh_track(pos_integer(), pos_integer()) :: RefreshTrack.result()
  def refresh_track(file_id, revision),
    do: RefreshTrack.call(file_id, revision, EctoObservationsReader, EctoMusicRepository)
end

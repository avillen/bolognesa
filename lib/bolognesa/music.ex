defmodule Bolognesa.Music do
  @moduledoc "Local music identities, import and authorized listening reads."
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Music.Application.UseCases.{RefreshTrack, RetryImport}
  alias Bolognesa.Music.Infrastructure.Readers.EctoObservationsReader
  alias Bolognesa.Music.Infrastructure.Repositories.{EctoImportRepository, EctoMusicRepository}
  @spec refresh_track(pos_integer(), pos_integer()) :: RefreshTrack.result()
  def refresh_track(file_id, revision),
    do: RefreshTrack.call(file_id, revision, EctoObservationsReader, EctoMusicRepository)

  @spec retry_import(Actor.t() | nil, pos_integer()) :: RetryImport.result()
  def retry_import(actor, file_id), do: RetryImport.call(actor, file_id, EctoImportRepository)
end

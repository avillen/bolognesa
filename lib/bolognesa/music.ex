defmodule Bolognesa.Music do
  @moduledoc "Local music identities, import and authorized listening reads."
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Music.Application.UseCases.{ListTracks, RefreshTrack, RetryImport}
  alias Bolognesa.Music.Infrastructure.Readers.{EctoObservationsReader, EctoTracksReader}
  alias Bolognesa.Music.Infrastructure.Repositories.{EctoImportRepository, EctoMusicRepository}
  @spec refresh_track(pos_integer(), pos_integer()) :: RefreshTrack.result()
  def refresh_track(file_id, revision),
    do: RefreshTrack.call(file_id, revision, EctoObservationsReader, EctoMusicRepository)

  @spec retry_import(Actor.t() | nil, pos_integer()) :: RetryImport.result()
  def retry_import(actor, file_id), do: RetryImport.call(actor, file_id, EctoImportRepository)

  @spec list_tracks(Actor.t() | nil, String.t(), pos_integer(), pos_integer() | nil) ::
          ListTracks.result()
  def list_tracks(actor, query, page, library_id),
    do: ListTracks.call(actor, query, page, library_id, EctoTracksReader)
end

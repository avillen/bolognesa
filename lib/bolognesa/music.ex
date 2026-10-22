defmodule Bolognesa.Music do
  @moduledoc "Local music identities, import and authorized listening reads."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser

  alias Bolognesa.Music.Application.UseCases.{
    AlbumTracks,
    Browse,
    ListTracks,
    RefreshTrack,
    RetryImport
  }

  alias Bolognesa.Music.Infrastructure.Readers.{EctoObservationsReader, EctoTracksReader}
  alias Bolognesa.Music.Infrastructure.Repositories.{EctoImportRepository, EctoMusicRepository}
  @type transaction_repository :: atom()
  @type import_request :: %{
          required(:file_id) => pos_integer(),
          required(:revision) => pos_integer(),
          required(:inspection_token) => String.t()
        }

  @doc "Accepts a current audio observation inside the caller's database transaction."
  @spec request_import_in_transaction!(transaction_repository(), import_request()) ::
          :requested | :unchanged | :stale
  def request_import_in_transaction!(repo, request),
    do: EctoImportRepository.request_in_transaction!(repo, request)

  @spec refresh_track(pos_integer(), pos_integer(), String.t() | nil, RefreshTrack.correlation()) ::
          RefreshTrack.result()
  def refresh_track(file_id, revision, token \\ nil, correlation \\ %{}),
    do:
      RefreshTrack.call(
        file_id,
        revision,
        EctoObservationsReader,
        EctoMusicRepository,
        token,
        correlation
      )

  @spec retry_import(AuthenticatedUser.t() | nil, pos_integer()) :: RetryImport.result()
  def retry_import(actor, file_id), do: RetryImport.call(actor, file_id, EctoImportRepository)

  @spec list_tracks(AuthenticatedUser.t() | nil, String.t(), pos_integer(), pos_integer() | nil) ::
          ListTracks.result()
  def list_tracks(actor, query, page, library_id),
    do: ListTracks.call(actor, query, page, library_id, EctoTracksReader)

  @spec browse(
          AuthenticatedUser.t() | nil,
          :artists | :albums,
          pos_integer() | nil,
          String.t(),
          pos_integer(),
          pos_integer() | nil
        ) :: Browse.result()
  def browse(actor, kind, artist, query, page, library),
    do:
      Browse.call(
        actor,
        kind,
        artist,
        query,
        page,
        library,
        Bolognesa.Music.Infrastructure.Readers.EctoBrowseReader
      )

  @spec list_album_tracks(
          AuthenticatedUser.t() | nil,
          pos_integer(),
          String.t(),
          pos_integer(),
          pos_integer() | nil
        ) :: AlbumTracks.result()
  def list_album_tracks(actor, album, query, page, library),
    do: AlbumTracks.call(actor, album, query, page, library, EctoTracksReader)

  @spec album_queue(AuthenticatedUser.t() | nil, pos_integer(), pos_integer() | nil) ::
          AlbumTracks.queue_result()
  def album_queue(actor, album, library),
    do: AlbumTracks.queue(actor, album, library, EctoTracksReader)
end

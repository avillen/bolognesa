defmodule Bolognesa.Music do
  @moduledoc "Local music identities, import and authorized listening reads."
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser

  alias Bolognesa.Music.Application.UseCases.{
    AlbumTracks,
    Browse,
    FetchTrack,
    ListRecentAlbums,
    ListTracks,
    RecordListening,
    RefreshTrack,
    RetryImport
  }

  alias Bolognesa.Music.Domain.Entities.{Album, Artist}
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

  @spec record_listening(AuthenticatedUser.t() | nil, integer(), integer()) ::
          RecordListening.result()
  def record_listening(actor, track_id, file_id),
    do:
      RecordListening.call(
        actor,
        track_id,
        file_id,
        EctoTracksReader,
        Bolognesa.Music.Infrastructure.Repositories.EctoListeningActivityRepository
      )

  @spec retry_import(AuthenticatedUser.t() | nil, pos_integer()) :: RetryImport.result()
  def retry_import(actor, file_id), do: RetryImport.call(actor, file_id, EctoImportRepository)

  @spec fetch_track(AuthenticatedUser.t() | nil, integer()) :: FetchTrack.result()
  def fetch_track(actor, track_id), do: FetchTrack.call(actor, track_id, EctoTracksReader)

  @doc "Lists up to three recently heard albums within the selected library, or all libraries."
  @spec list_recent_albums(AuthenticatedUser.t() | nil, pos_integer() | nil) ::
          ListRecentAlbums.result()
  def list_recent_albums(actor, library_id),
    do:
      ListRecentAlbums.call(
        actor,
        library_id,
        Bolognesa.Music.Infrastructure.Readers.EctoBrowseReader
      )

  @spec list_tracks(AuthenticatedUser.t() | nil, String.t(), pos_integer(), pos_integer() | nil) ::
          ListTracks.result()
  def list_tracks(actor, query, page, library_id),
    do: ListTracks.call(actor, query, page, library_id, EctoTracksReader)

  @spec browse(
          AuthenticatedUser.t() | nil,
          :artists | :albums,
          Artist.id() | nil,
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
          Album.id(),
          String.t(),
          pos_integer(),
          pos_integer() | nil
        ) :: AlbumTracks.result()
  def list_album_tracks(actor, album, query, page, library),
    do: AlbumTracks.call(actor, album, query, page, library, EctoTracksReader)

  @spec album_queue(AuthenticatedUser.t() | nil, Album.id(), pos_integer() | nil) ::
          AlbumTracks.queue_result()
  def album_queue(actor, album, library),
    do: AlbumTracks.queue(actor, album, library, EctoTracksReader)
end

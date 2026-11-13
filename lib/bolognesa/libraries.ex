defmodule Bolognesa.Libraries do
  @moduledoc "Configure and read media libraries."
  alias Bolognesa.Accounts, as: BolognesaAccounts
  alias Bolognesa.Libraries.Application.UseCases.CreateLibrary
  alias Bolognesa.Libraries.Application.UseCases.FetchInspectionCounts
  alias Bolognesa.Libraries.Application.UseCases.FetchScanStatus
  alias Bolognesa.Libraries.Application.UseCases.ListLibraries
  alias Bolognesa.Libraries.Application.UseCases.RequestInspectionRefresh
  alias Bolognesa.Libraries.Application.UseCases.StartScan

  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.Entities.MediaFile
  alias Bolognesa.Libraries.Domain.Entities.Scan
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.InspectionCounts
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewLibrary

  alias Bolognesa.Libraries.Infrastructure.Services.LocalFileSource

  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoLibraryRepository
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  @spec request_inspection_refresh(AuthenticatedUser.t() | nil, MediaFile.id(), pos_integer()) ::
          Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository.refresh_result()
          | {:error, :forbidden}
  def request_inspection_refresh(actor, file_id, expected_revision),
    do: RequestInspectionRefresh.call(actor, file_id, expected_revision, EctoInspectionRepository)

  @spec subscribe_status_updates(AuthenticatedUser.t() | nil) ::
          :ok | {:error, :forbidden | :unavailable}
  def subscribe_status_updates(actor) do
    with :ok <- BolognesaAccounts.authorize(actor, :admin) do
      LibraryStatusNotifications.subscribe()
    end
  end

  @spec create_library(AuthenticatedUser.t() | nil, NewLibrary.attrs()) ::
          {:ok, Library.t()}
          | {:error,
             NewLibrary.error()
             | :forbidden
             | :duplicate_source
             | :source_inaccessible
             | :source_outside_roots
             | :unavailable}
  def create_library(actor, attrs),
    do: CreateLibrary.call(actor, attrs, EctoLibraryRepository, LocalFileSource)

  @spec list_libraries(AuthenticatedUser.t() | nil) ::
          {:ok, [Library.t()]} | {:error, :forbidden | :unavailable}
  def list_libraries(actor), do: ListLibraries.call(actor, EctoLibraryRepository)

  @spec start_scan(AuthenticatedUser.t() | nil, Library.id(), keyword()) ::
          {:ok, Scan.t()} | {:error, :forbidden | :not_found | :scan_in_progress | :unavailable}
  def start_scan(actor, library_id, opts \\ []),
    do: StartScan.call(actor, library_id, EctoScanRepository, LibraryStatusNotifications, opts)

  @spec fetch_scan_status(AuthenticatedUser.t() | nil, Library.id()) ::
          {:ok, ScanStatus.t()} | {:error, :forbidden | :not_found | :unavailable}
  def fetch_scan_status(actor, library_id),
    do: FetchScanStatus.call(actor, library_id, EctoScanRepository)

  @spec fetch_inspection_counts(AuthenticatedUser.t() | nil, Library.id()) ::
          {:ok, InspectionCounts.t()} | {:error, :forbidden | :not_found | :unavailable}
  def fetch_inspection_counts(actor, library_id),
    do: FetchInspectionCounts.call(actor, library_id, EctoInspectionRepository)
end

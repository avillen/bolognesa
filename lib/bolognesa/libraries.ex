defmodule Bolognesa.Libraries do
  @moduledoc "Configure and read media libraries."
  alias Bolognesa.Libraries.Application.UseCases.{
    CreateLibrary,
    FetchInspectionCounts,
    FetchScanStatus,
    ListLibraries,
    StartScan
  }

  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.Entities.Scan
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.InspectionCounts
  alias Bolognesa.Libraries.Domain.ReadModels.Scans.ScanStatus
  alias Bolognesa.Libraries.Domain.ValueObjects.Files.NewLibrary

  alias Bolognesa.Libraries.Infrastructure.Services.LocalFileSource

  alias Bolognesa.Libraries.Infrastructure.Repositories.{
    EctoInspectionRepository,
    EctoLibraryRepository,
    EctoScanRepository
  }

  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Libraries.Infrastructure.Services.LibraryStatusNotifications

  @spec subscribe_status_updates(AuthenticatedUser.t() | nil) ::
          :ok | {:error, :forbidden | :unavailable}
  def subscribe_status_updates(actor) do
    with :ok <- Bolognesa.Accounts.authorize(actor, :admin) do
      LibraryStatusNotifications.subscribe()
    end
  end

  @spec create_library(AuthenticatedUser.t(), NewLibrary.attrs()) ::
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

  @spec list_libraries(AuthenticatedUser.t()) ::
          {:ok, [Library.t()]} | {:error, :forbidden | :unavailable}
  def list_libraries(actor), do: ListLibraries.call(actor, EctoLibraryRepository)

  @spec start_scan(AuthenticatedUser.t(), Library.id(), keyword()) ::
          {:ok, Scan.t()} | {:error, :forbidden | :not_found | :scan_in_progress | :unavailable}
  def start_scan(actor, library_id, opts \\ []),
    do: StartScan.call(actor, library_id, EctoScanRepository, LibraryStatusNotifications, opts)

  @spec fetch_scan_status(AuthenticatedUser.t(), Library.id()) ::
          {:ok, ScanStatus.t()} | {:error, :forbidden | :not_found | :unavailable}
  def fetch_scan_status(actor, library_id),
    do: FetchScanStatus.call(actor, library_id, EctoScanRepository)

  @spec fetch_inspection_counts(AuthenticatedUser.t(), Library.id()) ::
          {:ok, InspectionCounts.t()} | {:error, :forbidden | :not_found | :unavailable}
  def fetch_inspection_counts(actor, library_id),
    do: FetchInspectionCounts.call(actor, library_id, EctoInspectionRepository)
end

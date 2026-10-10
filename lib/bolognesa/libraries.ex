defmodule Bolognesa.Libraries do
  @moduledoc "Configure and read media libraries."
  alias Bolognesa.Libraries.Application.{
    CreateLibrary,
    GetInspectionCounts,
    GetScanStatus,
    ListLibraries,
    StartScan
  }

  alias Bolognesa.Libraries.Domain.{InspectionCounts, Library, NewLibrary, Scan, ScanStatus}
  alias Bolognesa.Libraries.Infrastructure.LocalFileSource

  alias Bolognesa.Libraries.Infrastructure.Persistence.{
    EctoInspectionRepository,
    EctoLibraryRepository,
    EctoScanRepository
  }

  alias Bolognesa.Identity.Domain.Actor

  @spec create_library(Actor.t(), NewLibrary.attrs()) ::
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

  @spec list_libraries(Actor.t()) ::
          {:ok, [Library.t()]} | {:error, :forbidden | :unavailable}
  def list_libraries(actor), do: ListLibraries.call(actor, EctoLibraryRepository)

  @spec start_scan(Actor.t(), Library.id(), keyword()) ::
          {:ok, Scan.t()} | {:error, :forbidden | :not_found | :scan_in_progress | :unavailable}
  def start_scan(actor, library_id, opts \\ []),
    do: StartScan.call(actor, library_id, EctoScanRepository, opts)

  @spec get_scan_status(Actor.t(), Library.id()) ::
          {:ok, ScanStatus.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_scan_status(actor, library_id),
    do: GetScanStatus.call(actor, library_id, EctoScanRepository)

  @spec get_inspection_counts(Actor.t(), Library.id()) ::
          {:ok, InspectionCounts.t()} | {:error, :forbidden | :not_found | :unavailable}
  def get_inspection_counts(actor, library_id),
    do: GetInspectionCounts.call(actor, library_id, EctoInspectionRepository)
end

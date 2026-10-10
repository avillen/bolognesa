defmodule Bolognesa.Libraries.Application.Ports.InspectionRepository do
  @moduledoc "Atomic state transitions for a current technical inspection token."

  alias Bolognesa.Libraries.Domain.{
    Inspection,
    InspectionCounts,
    Library,
    MediaFile,
    TechnicalMedia
  }

  @type adapter :: module()
  @callback counts(Library.id()) ::
              {:ok, InspectionCounts.t()} | {:error, :not_found | :unavailable}
  @callback get(MediaFile.id()) :: {:ok, Inspection.t()} | {:error, :not_found | :unavailable}
  @callback begin_inspection(MediaFile.id(), String.t(), integer() | nil) ::
              {:ok, MediaFile.t(), Library.t()} | {:ok, :stale} | {:error, :unavailable}
  @callback complete_inspection(MediaFile.id(), String.t(), TechnicalMedia.t()) ::
              :ok | {:ok, :stale} | {:error, :unavailable}
  @callback fail_inspection(MediaFile.id(), String.t(), Inspection.reason(), pos_integer()) ::
              :ok | {:ok, :stale} | {:error, :unavailable}
  @callback reconcile_jobs(DateTime.t()) :: :ok | {:error, :unavailable}
end

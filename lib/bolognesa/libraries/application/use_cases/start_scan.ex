defmodule Bolognesa.Libraries.Application.UseCases.StartScan do
  @moduledoc "Authorizes and persists a scan request, then signals its queued state."
  alias Bolognesa.Identity
  alias Bolognesa.Identity.Domain.Entities.Actor
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.Entities.Scan

  @spec call(
          Actor.t(),
          Library.id(),
          ScanRepository.adapter(),
          LibraryStatusNotifier.adapter(),
          keyword()
        ) ::
          {:ok, Scan.t()} | {:error, :forbidden | :not_found | :scan_in_progress | :unavailable}
  def call(actor, library_id, repository, notifications, opts \\ []) do
    with :ok <- Identity.authorize(actor, :admin),
         {:ok, scan} <-
           repository.request(library_id, Keyword.get(opts, :force_inspection?, false)) do
      notifications.notify(scan.library_id)
      {:ok, scan}
    end
  end
end

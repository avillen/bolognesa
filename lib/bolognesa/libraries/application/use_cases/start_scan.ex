defmodule Bolognesa.Libraries.Application.UseCases.StartScan do
  @moduledoc "Authorizes and persists a scan request, then signals its queued state."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Domain.Entities.Library
  alias Bolognesa.Libraries.Domain.Entities.Scan

  @spec call(
          AuthenticatedUser.t(),
          Library.id(),
          ScanRepository.adapter(),
          LibraryStatusNotifier.adapter(),
          keyword()
        ) ::
          {:ok, Scan.t()} | {:error, :forbidden | :not_found | :scan_in_progress | :unavailable}
  def call(actor, library_id, repository, notifications, opts \\ []) do
    with :ok <- Accounts.authorize(actor, :admin),
         force_inspection = Keyword.get(opts, :force_inspection?, false),
         {:ok, scan} <- repository.request(library_id, force_inspection) do
      Events.emit(:libraries, :scan, :requested, %{
        library_id: scan.library_id,
        scan_id: scan.id,
        job_id: scan.job_id
      })

      notifications.notify(scan.library_id)
      {:ok, scan}
    else
      {:error, :unavailable} = error ->
        Events.emit(:libraries, :scan, :retryable, %{
          library_id: library_id,
          reason: :storage_unavailable,
          operation: :request
        })

        error

      error ->
        error
    end
  end
end

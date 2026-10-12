defmodule Bolognesa.Libraries.Application.UseCases.ReconcileScans do
  @moduledoc "Recovers scans and notifies changes confirmed before any recovery failure."

  alias Bolognesa.Libraries.Application.Ports.Repositories.ScanRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier

  @type result :: :ok | {:error, :unavailable}

  @spec call(DateTime.t(), ScanRepository.adapter(), LibraryStatusNotifier.adapter()) :: result()
  def call(now, repository, notifications) do
    result = repository.reconcile_jobs(now)
    Enum.each(Enum.uniq(result.changed_library_ids), &notifications.notify/1)
    outcome(result.error)
  end

  defp outcome(nil), do: :ok
  defp outcome(:unavailable), do: {:error, :unavailable}
end

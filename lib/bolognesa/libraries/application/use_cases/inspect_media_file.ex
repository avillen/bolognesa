defmodule Bolognesa.Libraries.Application.UseCases.InspectMediaFile do
  @moduledoc "Runs one token protected inspection outside a database transaction."

  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Application.Ports.Services.{LibraryStatusNotifier, MediaProbe}
  alias Bolognesa.Libraries.Domain.Entities.{Inspection, MediaFile}
  alias Bolognesa.Libraries.Infrastructure.Jobs.InspectionPolicy

  @permanent [
    :source_changed,
    :source_inaccessible,
    :unsafe_entry,
    :unreadable,
    :unsupported,
    :invalid_output
  ]
  @transient [:timeout, :tool_unavailable, :storage_unavailable, :unexpected_failure]

  @type result :: :ok | {:error, Inspection.reason() | :storage_unavailable}

  @spec call(
          MediaFile.id(),
          String.t(),
          pos_integer(),
          InspectionRepository.adapter(),
          MediaProbe.adapter(),
          LibraryStatusNotifier.adapter(),
          integer() | nil
        ) ::
          result()
  def call(file_id, token, attempt, repository, probe, notifications, job_id \\ nil) do
    case repository.begin_inspection(file_id, token, job_id) do
      {:ok, :stale} ->
        :ok

      {:ok, file, library} ->
        notifications.notify(library.id)
        inspect_current(file, library, token, attempt, repository, probe, notifications)

      {:error, :unavailable} ->
        {:error, :storage_unavailable}
    end
  end

  defp inspect_current(file, library, token, attempt, repository, probe, notifications) do
    case probe.inspect(library, file) do
      {:ok, technical_media} ->
        complete(file, token, technical_media, repository, notifications)

      {:error, reason} when reason in @permanent ->
        record_failure(file, token, reason, attempt, repository, notifications, :cancel)

      {:error, reason} when reason in @transient ->
        retry_or_fail(file, token, reason, attempt, repository, notifications)

      _ ->
        {:error, :unexpected_failure}
    end
  end

  defp complete(file, token, technical_media, repository, notifications) do
    case repository.complete_inspection(file.id, token, technical_media) do
      :ok -> notifications.notify(file.library_id)
      {:ok, :stale} -> :ok
      {:error, :unavailable} -> {:error, :storage_unavailable}
    end
  end

  defp retry_or_fail(file, token, reason, attempt, repository, notifications) do
    if attempt >= InspectionPolicy.max_attempts(),
      do: record_failure(file, token, reason, attempt, repository, notifications, :error),
      else: {:error, reason}
  end

  defp record_failure(file, token, reason, attempt, repository, notifications, disposition) do
    case repository.fail_inspection(file.id, token, reason, attempt) do
      :ok ->
        notifications.notify(file.library_id)
        failure_result(disposition, reason)

      {:ok, :stale} ->
        :ok

      {:error, :unavailable} ->
        {:error, :storage_unavailable}
    end
  end

  defp failure_result(:cancel, _reason), do: :ok
  defp failure_result(:error, reason), do: {:error, reason}
end

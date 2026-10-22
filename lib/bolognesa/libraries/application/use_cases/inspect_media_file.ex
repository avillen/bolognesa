defmodule Bolognesa.Libraries.Application.UseCases.InspectMediaFile do
  @moduledoc "Runs one token protected inspection outside a database transaction."

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Application.Ports.Services.{LibraryStatusNotifier, MediaProbe}
  alias Bolognesa.Libraries.Domain.Entities.{Inspection, MediaFile}

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
        ) :: result()
  def call(file_id, token, attempt, repository, probe, notifications, job_id \\ nil) do
    metadata = %{file_id: file_id, job_id: job_id, attempt: attempt}
    started = Events.started_at()

    case repository.begin_inspection(file_id, token, job_id) do
      {:ok, :stale} ->
        observe(:stale, metadata, started, :stale_attempt)
        :ok

      {:ok, file, library} ->
        metadata = Map.merge(metadata, %{library_id: library.id, revision: file.revision})
        Events.emit(:libraries, :inspection, :started, metadata)
        notifications.notify(library.id)

        inspect_current(
          file,
          token,
          attempt,
          repository,
          notifications,
          {metadata, started},
          probe_result(probe, library, file)
        )

      {:error, :unavailable} ->
        observe(:retryable, metadata, started, :storage_unavailable)
        {:error, :storage_unavailable}
    end
  end

  defp probe_result(probe, library, file) do
    Code.ensure_loaded(probe)

    if function_exported?(probe, :inspect_with_diagnostics, 2),
      do: probe.inspect_with_diagnostics(library, file),
      else: probe.inspect(library, file)
  end

  defp inspect_current(
         file,
         token,
         attempt,
         repository,
         notifications,
         context,
         {:error, reason, stage}
       ) do
    {metadata, started} = context

    inspect_current(
      file,
      token,
      attempt,
      repository,
      notifications,
      {Map.put(metadata, :failure_stage, stage), started},
      {:error, reason}
    )
  end

  defp inspect_current(
         file,
         token,
         _attempt,
         repository,
         notifications,
         context,
         {:ok, technical_media}
       ) do
    finish(
      repository.complete_inspection(file.id, token, technical_media),
      file,
      notifications,
      context,
      :completed,
      nil,
      :ok
    )
  end

  defp inspect_current(file, token, attempt, repository, notifications, context, {:error, reason})
       when reason in @permanent do
    record_failure(file, token, reason, attempt, repository, notifications, context, :ok)
  end

  defp inspect_current(file, token, attempt, repository, notifications, context, {:error, reason})
       when reason in @transient do
    retry_or_fail(file, token, reason, attempt, repository, notifications, context)
  end

  defp inspect_current(
         _file,
         _token,
         _attempt,
         _repository,
         _notifications,
         {metadata, started},
         _
       ) do
    observe(:retryable, metadata, started, :unexpected_failure)
    {:error, :unexpected_failure}
  end

  defp retry_or_fail(file, token, reason, attempt, repository, notifications, context) do
    if attempt >= Inspection.max_attempts() do
      record_failure(
        file,
        token,
        reason,
        attempt,
        repository,
        notifications,
        context,
        {:error, reason}
      )
    else
      {metadata, started} = context
      observe(:retryable, metadata, started, reason)
      {:error, reason}
    end
  end

  defp record_failure(file, token, reason, attempt, repository, notifications, context, result) do
    finish(
      repository.fail_inspection(file.id, token, reason, attempt),
      file,
      notifications,
      context,
      :failed,
      reason,
      result
    )
  end

  defp finish(:ok, file, notifications, {metadata, started}, outcome, reason, result) do
    observe(outcome, metadata, started, reason)
    notifications.notify(file.library_id)
    result
  end

  defp finish(
         {:ok, :stale},
         _file,
         _notifications,
         {metadata, started},
         _outcome,
         _reason,
         _result
       ) do
    observe(:stale, metadata, started, :stale_attempt)
    :ok
  end

  defp finish(
         {:error, :unavailable},
         _file,
         _notifications,
         {metadata, started},
         _outcome,
         _reason,
         _result
       ) do
    observe(
      :retryable,
      Map.put(metadata, :failure_stage, :persistence),
      started,
      :storage_unavailable
    )

    {:error, :storage_unavailable}
  end

  defp observe(outcome, metadata, started, reason) do
    metadata = if reason, do: Map.put(metadata, :reason, reason), else: metadata

    Events.emit(:libraries, :inspection, outcome, metadata, %{
      duration_ms: Events.elapsed(started)
    })
  end
end

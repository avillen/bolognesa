defmodule Bolognesa.Libraries.Application.UseCases.InspectMediaFile do
  @moduledoc "Runs one token protected inspection outside a database transaction."

  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Libraries.Application.Ports.Repositories.InspectionRepository
  alias Bolognesa.Libraries.Application.Ports.Services.LibraryStatusNotifier
  alias Bolognesa.Libraries.Application.Ports.Services.MediaProbe
  alias Bolognesa.Libraries.Domain.Entities.Inspection
  alias Bolognesa.Libraries.Domain.Entities.MediaFile

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

        context = %{
          file: file,
          token: token,
          attempt: attempt,
          repository: repository,
          notifications: notifications,
          metadata: metadata,
          started: started
        }

        inspect_current(context, probe.inspect(library, file))

      {:error, :unavailable} ->
        observe(:retryable, metadata, started, :storage_unavailable)
        {:error, :storage_unavailable}
    end
  end

  defp inspect_current(context, {:error, reason, stage}) do
    metadata = Map.put(context.metadata, :failure_stage, stage)
    inspect_current(%{context | metadata: metadata}, {:error, reason})
  end

  defp inspect_current(context, {:ok, technical_media}) do
    result = context.repository.complete_inspection(context.file.id, context.token, technical_media)
    finish(result, context, :completed, nil, :ok)
  end

  defp inspect_current(context, {:error, reason}) when reason in @permanent,
    do: record_failure(context, reason, :ok)

  defp inspect_current(context, {:error, reason}) when reason in @transient,
    do: retry_or_fail(context, reason)

  defp inspect_current(context, _result) do
    observe(:retryable, context.metadata, context.started, :unexpected_failure)
    {:error, :unexpected_failure}
  end

  defp retry_or_fail(context, reason) do
    if context.attempt >= Inspection.max_attempts() do
      record_failure(context, reason, {:error, reason})
    else
      observe(:retryable, context.metadata, context.started, reason)
      {:error, reason}
    end
  end

  defp record_failure(context, reason, result) do
    stored = context.repository.fail_inspection(context.file.id, context.token, reason)
    finish(stored, context, :failed, reason, result)
  end

  defp finish(:ok, context, outcome, reason, result) do
    observe(outcome, context.metadata, context.started, reason)
    context.notifications.notify(context.file.library_id)
    result
  end

  defp finish({:ok, :stale}, context, _outcome, _reason, _result) do
    observe(:stale, context.metadata, context.started, :stale_attempt)
    :ok
  end

  defp finish({:error, :unavailable}, context, _outcome, _reason, _result) do
    metadata = Map.put(context.metadata, :failure_stage, :persistence)
    observe(:retryable, metadata, context.started, :storage_unavailable)
    {:error, :storage_unavailable}
  end

  defp observe(outcome, metadata, started, reason) do
    metadata = if reason, do: Map.put(metadata, :reason, reason), else: metadata

    Events.emit(:libraries, :inspection, outcome, metadata, %{
      duration_ms: Events.elapsed(started)
    })
  end
end

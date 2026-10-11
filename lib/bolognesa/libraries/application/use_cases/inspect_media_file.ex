defmodule Bolognesa.Libraries.Application.UseCases.InspectMediaFile do
  @moduledoc "Runs one token protected inspection outside a database transaction."

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

  @spec call(pos_integer(), String.t(), pos_integer(), module(), module(), integer() | nil) ::
          :ok | {:cancel, atom()} | {:error, atom()}
  def call(file_id, token, attempt, repository, probe, job_id \\ nil) do
    case repository.begin_inspection(file_id, token, job_id) do
      {:ok, :stale} ->
        :ok

      {:ok, file, library} ->
        inspect_current(file_id, token, attempt, repository, probe, library, file)

      {:error, :unavailable} ->
        {:error, :storage_unavailable}
    end
  end

  defp inspect_current(file_id, token, attempt, repository, probe, library, file) do
    case probe.inspect(library, file) do
      {:ok, technical_media} ->
        case repository.complete_inspection(file_id, token, technical_media) do
          :ok -> :ok
          {:ok, :stale} -> :ok
          {:error, :unavailable} -> {:error, :storage_unavailable}
        end

      {:error, reason} when reason in @permanent ->
        record_failure(file_id, token, reason, attempt, repository, :cancel)

      {:error, reason} when reason in @transient ->
        if attempt >= InspectionPolicy.max_attempts() do
          record_failure(file_id, token, reason, attempt, repository, :error)
        else
          {:error, reason}
        end

      _ ->
        {:error, :unexpected_failure}
    end
  end

  defp record_failure(file_id, token, reason, attempt, repository, disposition) do
    case repository.fail_inspection(file_id, token, reason, attempt) do
      :ok -> if(disposition == :cancel, do: :ok, else: {:error, reason})
      {:ok, :stale} -> :ok
      {:error, :unavailable} -> {:error, :storage_unavailable}
    end
  end
end

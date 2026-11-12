defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository.ObanJobRecovery do
  @moduledoc "Reconciles scan state against its linked jobs."
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.ScanSchema
  alias Bolognesa.Libraries.Domain.Entities.Scan
  alias Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult
  alias Bolognesa.Libraries.Infrastructure.Jobs.Policies.ScanPolicy
  alias Bolognesa.Libraries.Infrastructure.Repositories.EctoScanRepository.ScanMapper
  alias Bolognesa.Repo

  @spec reconcile(DateTime.t()) :: ReconciliationResult.t()
  def reconcile(now) do
    cutoff = DateTime.add(now, -ScanPolicy.timeout_ms(), :millisecond)

    candidates =
      Repo.all(
        from scan in ScanSchema,
          left_join: job in Oban.Job,
          on: job.id == scan.job_id,
          where: scan.state in [:queued, :running, :retrying],
          where:
            is_nil(job.id) or job.state in ["retryable", "discarded", "cancelled", "completed"],
          where:
            scan.state != :running or is_nil(scan.attempt_started_at) or
              scan.attempt_started_at <= ^cutoff,
          where:
            not (scan.state == :retrying and not is_nil(job.id) and job.state == "retryable"),
          order_by: scan.id,
          limit: 100,
          select: scan.id
      )

    Enum.reduce_while(candidates, %ReconciliationResult{}, fn id, result ->
      reconcile_result(
        transaction(fn -> reconcile_locked(locked_scan(id, :not_found), now) end),
        result
      )
    end)
  rescue
    DBConnection.ConnectionError -> %ReconciliationResult{error: :unavailable}
    Postgrex.Error -> %ReconciliationResult{error: :unavailable}
  end

  defp reconcile_locked(%ScanSchema{state: state}, _now) when state in [:completed, :failed],
    do: {:ok, []}

  defp reconcile_locked(scan, now) do
    if attempt_within_budget?(scan, now),
      do: {:ok, []},
      else: reconcile_job(scan, reconciliation_job(scan.job_id), now)
  end

  defp reconciliation_job(nil), do: nil
  defp reconciliation_job(id), do: Repo.get(Oban.Job, id)

  defp attempt_within_budget?(
         %ScanSchema{state: :running, attempt_started_at: %DateTime{} = started},
         now
       ),
       do: DateTime.diff(now, started, :millisecond) < ScanPolicy.timeout_ms()

  defp attempt_within_budget?(_scan, _now), do: false

  defp reconcile_job(scan, nil, now),
    do: reconcile_transition(scan, :failed, :unexpected_failure, now)

  defp reconcile_job(scan, %{state: "discarded"}, now),
    do: reconcile_transition(scan, :failed, :attempts_exhausted, now)

  defp reconcile_job(scan, %{state: state}, now) when state in ["cancelled", "completed"],
    do: reconcile_transition(scan, :failed, :unexpected_failure, now)

  defp reconcile_job(%ScanSchema{state: :retrying}, %{state: "retryable"}, _now),
    do: {:ok, []}

  defp reconcile_job(scan, %{state: "retryable"}, now),
    do: reconcile_transition(scan, :retrying, :unexpected_failure, now)

  defp reconcile_job(_scan, _job, _now), do: {:ok, []}

  defp reconcile_transition(scan, state, fallback, now) do
    reason = scan.failure_reason || fallback

    case Scan.transition(ScanMapper.to_scan(scan), state, reason, now) do
      {:ok, transitioned} ->
        _stored = save_scan(scan, transitioned)
        {:ok, [scan.library_id]}

      _ ->
        Repo.rollback(:unavailable)
    end
  end

  defp reconcile_result({:ok, library_ids}, result),
    do: {:cont, %{result | changed_library_ids: library_ids ++ result.changed_library_ids}}

  defp reconcile_result({:error, :not_found}, result), do: {:cont, result}
  defp reconcile_result({:error, _reason}, result), do: {:halt, %{result | error: :unavailable}}

  defp transaction(operation) do
    case Repo.transaction(operation) do
      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  defp locked_scan(scan_id, missing_reason) do
    case Repo.one(from scan in ScanSchema, where: scan.id == ^scan_id, lock: "FOR UPDATE") do
      nil -> Repo.rollback(missing_reason)
      scan -> scan
    end
  end

  defp save_scan(schema, scan) do
    attrs =
      Map.take(scan, [
        :state,
        :generation,
        :attempt,
        :files_discovered,
        :failure_reason,
        :started_at,
        :attempt_started_at,
        :finished_at,
        :updated_at
      ])

    case Repo.update(ScanSchema.changeset(schema, attrs)) do
      {:ok, stored} -> ScanMapper.to_scan(stored)
      {:error, _changeset} -> Repo.rollback(:unavailable)
    end
  end
end

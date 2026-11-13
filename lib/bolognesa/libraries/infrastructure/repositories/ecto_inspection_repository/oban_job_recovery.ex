defmodule Bolognesa.Libraries.Infrastructure.Repositories.EctoInspectionRepository.ObanJobRecovery do
  @moduledoc "Reconciles inspection state against its linked jobs."
  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Infrastructure.Persistence.MediaFileSchema
  alias Bolognesa.Libraries.Domain.ReadModels.ReconciliationResult
  alias Bolognesa.Libraries.Infrastructure.Jobs.Policies.InspectionPolicy
  alias Bolognesa.Repo

  @spec reconcile(DateTime.t()) :: ReconciliationResult.t()
  def reconcile(now) do
    cutoff = DateTime.add(now, -InspectionPolicy.rescue_after_ms(), :millisecond)

    ids = reconciliation_ids(cutoff)

    Enum.reduce_while(ids, %ReconciliationResult{}, fn id, result ->
      reconcile_id(id, cutoff, result)
    end)
  rescue
    DBConnection.ConnectionError -> %ReconciliationResult{error: :unavailable}
    Postgrex.Error -> %ReconciliationResult{error: :unavailable}
  end

  defp reconcile_id(id, cutoff, result) do
    case transaction(fn -> reconcile_one(id, cutoff) end) do
      {:ok, library_ids} ->
        {:cont, %{result | changed_library_ids: library_ids ++ result.changed_library_ids}}

      {:error, :unavailable} ->
        {:halt, %{result | error: :unavailable}}
    end
  end

  defp reconciliation_ids(cutoff) do
    Repo.all(
      from inspection in InspectionSchema,
        left_join: job in Oban.Job,
        on: job.id == inspection.job_id,
        where: inspection.state in [:pending, :running] and not is_nil(inspection.job_id),
        where:
          is_nil(job.id) or job.state in ["discarded", "cancelled", "completed"] or
            (inspection.state == :running and job.state in ["retryable", "available"]) or
            (inspection.state == :running and job.state == "executing" and
               inspection.started_at < ^cutoff and job.attempted_at < ^cutoff),
        order_by: inspection.id,
        limit: 100,
        select: inspection.id
    )
  end

  defp reconcile_one(id, cutoff) do
    inspection = Repo.one(from row in InspectionSchema, where: row.id == ^id, lock: "FOR UPDATE")

    if inspection && inspection.state in [:pending, :running] do
      reconcile_active(inspection, cutoff)
    else
      {:ok, []}
    end
  end

  defp reconcile_active(inspection, cutoff) do
    job = Repo.get(Oban.Job, inspection.job_id)

    if (inspection.state == :running and job) && job.state in ["retryable", "available"] do
      inspection
      |> InspectionSchema.changeset(%{state: :pending, started_at: nil})
      |> Repo.update!()

      reconciled(inspection)
    else
      fail_if_reason(inspection, job, cutoff)
    end
  end

  defp fail_if_reason(inspection, job, cutoff) do
    case reconciliation_reason(inspection, job, cutoff) do
      nil ->
        {:ok, []}

      reason ->
        inspection
        |> InspectionSchema.changeset(%{
          state: :failed,
          failure_reason: reason,
          finished_at: DateTime.utc_now()
        })
        |> Repo.update!()

        reconciled(inspection)
    end
  end

  defp reconciled(inspection) do
    file = Repo.get!(MediaFileSchema, inspection.media_file_id)
    {:ok, [file.library_id]}
  end

  defp reconciliation_reason(_inspection, nil, _cutoff), do: :unexpected_failure
  defp reconciliation_reason(_inspection, %{state: "discarded"}, _cutoff), do: :attempts_exhausted

  defp reconciliation_reason(_inspection, %{state: state}, _cutoff)
       when state in ["cancelled", "completed"],
       do: :unexpected_failure

  defp reconciliation_reason(
         %{state: :running, started_at: started},
         %{state: "executing", attempted_at: attempted},
         cutoff
       )
       when not is_nil(started) and not is_nil(attempted) do
    if DateTime.compare(started, cutoff) == :lt and DateTime.compare(attempted, cutoff) == :lt,
      do: :timeout,
      else: nil
  end

  defp reconciliation_reason(_inspection, _job, _cutoff), do: nil

  defp transaction(operation) do
    case Repo.transaction(operation) do
      {:ok, result} ->
        result

      {:error, _reason} ->
        {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end
end

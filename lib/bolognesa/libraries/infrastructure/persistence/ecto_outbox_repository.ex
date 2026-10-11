defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoOutboxRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.OutboxRepository

  import Ecto.Query

  alias Bolognesa.Infrastructure.Persistence.InspectionEventSchema
  alias Bolognesa.Infrastructure.Persistence.InspectionSchema
  alias Bolognesa.Repo

  @worker "Bolognesa.Libraries.Infrastructure.Jobs.InspectionWorker"
  @queue "media_inspections"

  @impl true
  def dispatch_batch(limit) when is_integer(limit) and limit > 0 do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:events, fn repo, _changes -> {:ok, lock_pending_events(repo, limit)} end)
    |> Oban.insert_all(:jobs, fn %{events: events} -> Enum.map(events, &inspection_job/1) end)
    |> Ecto.Multi.run(:linked, fn repo, %{jobs: jobs} -> link_jobs(repo, jobs) end)
    |> Ecto.Multi.run(:delivered, fn repo, %{events: events} -> mark_delivered(repo, events) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{events: events}} -> {:ok, length(events)}
      {:error, _step, _reason, _changes} -> {:error, :unavailable}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  defp lock_pending_events(repo, limit) do
    repo.all(
      from(event in InspectionEventSchema,
        where: is_nil(event.delivered_at),
        order_by: event.id,
        limit: ^limit,
        lock: "FOR UPDATE SKIP LOCKED"
      )
    )
  end

  defp inspection_job(event) do
    Oban.Job.new(%{media_file_id: event.media_file_id, token: event.token},
      worker: @worker,
      queue: @queue,
      max_attempts: 3
    )
  end

  defp mark_delivered(repo, events) do
    ids = Enum.map(events, & &1.id)

    {count, _} =
      repo.update_all(
        from(event in InspectionEventSchema, where: event.id in ^ids),
        set: [delivered_at: DateTime.utc_now()]
      )

    {:ok, count}
  end

  defp link_jobs(repo, jobs) do
    Enum.each(jobs, fn job ->
      %{"media_file_id" => file_id, "token" => token} = job.args

      repo.update_all(
        from(inspection in InspectionSchema,
          where: inspection.media_file_id == ^file_id and inspection.token == ^token
        ),
        set: [job_id: job.id]
      )
    end)

    {:ok, length(jobs)}
  end
end

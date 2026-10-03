defmodule Bolognesa.Libraries.Infrastructure.Persistence.EctoScanRepository do
  @moduledoc false
  @behaviour Bolognesa.Libraries.Application.Ports.ScanRepository

  import Ecto.Query
  alias Bolognesa.Repo
  alias Bolognesa.Libraries.Domain.ScanStatus
  alias Bolognesa.Libraries.Infrastructure.Persistence.EctoLibraryRepository.LibrarySchema
  alias __MODULE__.{ScanMapper, ScanSchema}

  @impl true
  def request(library_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:library, fn repo, _changes -> find_library(repo, library_id) end)
    |> Ecto.Multi.insert(
      :scan,
      ScanSchema.changeset(%ScanSchema{}, %{
        library_id: library_id,
        requested_at: DateTime.utc_now()
      })
    )
    |> Oban.insert(:job, fn %{scan: scan} ->
      Oban.Job.new(%{scan_id: scan.id},
        worker: "Bolognesa.Libraries.Infrastructure.Jobs.ScanWorker",
        queue: "library_scans",
        max_attempts: 3
      )
    end)
    |> Ecto.Multi.update(:referenced_scan, fn %{scan: scan, job: job} ->
      ScanSchema.changeset(scan, %{job_id: job.id})
    end)
    |> Repo.transaction()
    |> request_result()
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
    Ecto.ConstraintError -> {:error, :unavailable}
  end

  @impl true
  def status(library_id) do
    with {:ok, _library} <- find_library(Repo, library_id) do
      latest =
        Repo.one(
          from scan in ScanSchema,
            where: scan.library_id == ^library_id,
            order_by: [desc: scan.requested_at, desc: scan.id],
            limit: 1
        )

      last_completed_at =
        Repo.one(
          from scan in ScanSchema,
            where: scan.library_id == ^library_id and scan.state == :completed,
            select: max(scan.finished_at)
        )

      {:ok,
       %ScanStatus{
         library_id: library_id,
         latest_scan: map_latest(latest),
         last_completed_at: last_completed_at
       }}
    end
  rescue
    DBConnection.ConnectionError -> {:error, :unavailable}
    Postgrex.Error -> {:error, :unavailable}
  end

  @impl true
  def begin_attempt(_scan_id, _attempt), do: {:error, :unavailable}

  @impl true
  def save_batch(_scan_id, _generation, _entries), do: {:error, :unavailable}

  @impl true
  def complete(_scan_id, _generation), do: {:error, :unavailable}

  @impl true
  def fail(_scan_id, _generation, _reason, _state), do: {:error, :unavailable}

  @impl true
  def reconcile_jobs(_now), do: {:error, :unavailable}

  defp find_library(repo, library_id) do
    case repo.get(LibrarySchema, library_id) do
      nil -> {:error, :not_found}
      library -> {:ok, library}
    end
  end

  defp request_result({:ok, %{referenced_scan: scan}}), do: {:ok, ScanMapper.to_scan(scan)}
  defp request_result({:error, :library, :not_found, _changes}), do: {:error, :not_found}

  defp request_result({:error, :scan, changeset, _changes}),
    do: {:error, scan_insert_error(changeset)}

  defp request_result({:error, _step, _reason, _changes}), do: {:error, :unavailable}

  defp scan_insert_error(changeset) do
    if Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
         opts[:constraint] == :unique and opts[:constraint_name] == "library_scans_one_active"
       end), do: :scan_in_progress, else: :unavailable
  end

  defp map_latest(nil), do: nil
  defp map_latest(scan), do: ScanMapper.to_scan(scan)
end

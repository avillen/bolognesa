defmodule Bolognesa.Music.Infrastructure.Jobs.RefreshWorker do
  @moduledoc "Bounded durable music import with token and job ownership checks."
  alias Bolognesa.Music.Infrastructure.Jobs.ImportPolicy
  use Oban.Worker, queue: :music_imports, max_attempts: ImportPolicy.max_attempts()

  alias Bolognesa.Music
  alias Bolognesa.Music.Infrastructure.Repositories.EctoImportRepository

  @impl Oban.Worker
  def timeout(_job), do: ImportPolicy.timeout_ms()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => id, "revision" => revision}} = job)
      when is_integer(id) and id > 0 and is_integer(revision) and revision > 0 do
    case EctoImportRepository.begin_attempt(id, revision, job.id) do
      {:ok, :stale} -> :ok
      {:ok, attempt} -> refresh(job, attempt)
      {:error, :unavailable} -> {:error, :storage_unavailable}
    end
  rescue
    _error -> {:error, :unexpected_failure}
  catch
    _kind, _value -> {:error, :unexpected_failure}
  end

  def perform(_job), do: {:cancel, :unexpected_failure}

  defp refresh(job, attempt) do
    result =
      Music.refresh_track(
        attempt.media_file_id,
        attempt.observed_revision,
        attempt.inspection_token
      )

    if result != :ok && job.attempt >= job.max_attempts do
      EctoImportRepository.fail_attempt(attempt, :storage_unavailable)
    end

    result
  end
end

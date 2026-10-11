defmodule Bolognesa.Identification.Infrastructure.Jobs.IdentificationWorker do
  @moduledoc "Oban boundary for a token protected identification."
  use Oban.Worker, queue: :identifications, max_attempts: 3
  require Logger

  alias Bolognesa.Identification.Application.UseCases.IdentifyMediaFile
  alias Bolognesa.Identification.Application.UseCases.IdentifySeriesFile
  alias Bolognesa.Identification.Infrastructure.Providers.TmdbMovieProvider
  alias Bolognesa.Identification.Infrastructure.Providers.TmdbSeriesProvider
  alias Bolognesa.Identification.Infrastructure.Repositories.EctoIdentificationRepository

  @impl Oban.Worker
  def timeout(_job), do: 30_000

  @impl Oban.Worker
  def perform(job) do
    provider = Application.get_env(:bolognesa, :movie_provider_adapter, TmdbMovieProvider)

    series_provider =
      Application.get_env(:bolognesa, :series_provider_adapter, TmdbSeriesProvider)

    perform(job, EctoIdentificationRepository, provider, series_provider)
  end

  @spec perform(Oban.Job.t(), module(), module()) :: :ok | {:error, atom()} | {:cancel, atom()}
  def perform(job, repository, provider),
    do: perform(job, repository, provider, TmdbSeriesProvider)

  @spec perform(Oban.Job.t(), module(), module(), module()) ::
          :ok | {:error, atom()} | {:cancel, atom()}
  def perform(
        %Oban.Job{args: %{"file_id" => id, "token" => token}, attempt: attempt} = job,
        repository,
        movie_provider,
        series_provider
      )
      when is_integer(id) and id > 0 and is_binary(token) do
    case repository.find_file(id) do
      {:ok, %{content_type: :movie}} ->
        IdentifyMediaFile.call(id, token, attempt, repository, movie_provider, job.id)

      {:ok, %{content_type: :series}} ->
        IdentifySeriesFile.call(id, token, attempt, repository, series_provider, job.id)

      {:error, :not_found} ->
        :ok

      {:error, :unavailable} ->
        {:error, :unavailable}
    end
  rescue
    _ -> unexpected_failure(id, job.id, attempt)
  catch
    _, _ -> unexpected_failure(id, job.id, attempt)
  end

  def perform(_, _, _, _), do: {:cancel, :invalid_job}

  defp unexpected_failure(id, job_id, attempt) do
    Logger.warning("Identification job failed",
      file_id: id,
      job_id: job_id,
      attempt: attempt,
      reason: :unexpected_failure
    )

    {:error, :unexpected_failure}
  end
end

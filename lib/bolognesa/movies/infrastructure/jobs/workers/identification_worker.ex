defmodule Bolognesa.Movies.Infrastructure.Jobs.Workers.IdentificationWorker do
  @moduledoc "Runs a token-protected movie identification."
  use Oban.Worker, queue: :identifications, max_attempts: 3
  alias Bolognesa.Infrastructure.Jobs.IdentificationJob
  alias Bolognesa.Movies.Application.Ports.Providers.MovieProvider
  alias Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Movies.Application.UseCases.IdentifyMovieFile
  alias Bolognesa.Movies.Infrastructure.Providers.TmdbMovieProvider
  alias Bolognesa.Movies.Infrastructure.Repositories.EctoIdentificationRepository

  @impl Oban.Worker
  def timeout(_job), do: 30_000

  @impl Oban.Worker
  def perform(job),
    do:
      perform(
        job,
        EctoIdentificationRepository,
        Application.get_env(:bolognesa, :movie_provider_adapter, TmdbMovieProvider)
      )

  @spec perform(Oban.Job.t(), IdentificationRepository.adapter(), MovieProvider.adapter()) ::
          :ok
          | {:error, IdentificationRepository.reason() | :unusable_name | MovieProvider.reason()}
          | {:cancel, :invalid_job}
  def perform(job, repository, provider) do
    IdentificationJob.perform(job, :movies, fn id, token, attempt ->
      IdentifyMovieFile.call(id, token, attempt, repository, provider, job.id)
    end)
  end
end

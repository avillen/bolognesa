defmodule Bolognesa.Movies.Application.UseCases.RetryIdentification do
  @moduledoc "Request a new automatic identification unless a manual choice owns the file."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Movies.Application.Ports.Repositories.IdentificationRepository
  alias Bolognesa.Movies.Domain.Entities.Identification

  @spec call(AuthenticatedUser.t(), pos_integer(), IdentificationRepository.adapter()) ::
          {:ok, Identification.t()}
          | {:error,
             :forbidden | :not_found | :unavailable | :wrong_content_type | :manual_locked}
  def call(actor, file_id, repository) do
    with :ok <- Accounts.authorize(actor, :admin) do
      result = repository.retry(file_id)
      observe(result, actor.id, file_id)
      result
    end
  end

  defp observe({:ok, identification}, user_id, file_id) do
    Events.emit(:movies, :identification, :requested, %{
      user_id: user_id,
      file_id: file_id,
      job_id: identification.job_id,
      revision: identification.observed_revision,
      operation: :retry
    })
  end

  defp observe({:error, :unavailable}, user_id, file_id),
    do:
      Events.emit(:movies, :identification, :retryable, %{
        user_id: user_id,
        file_id: file_id,
        reason: :storage_unavailable,
        operation: :retry
      })

  defp observe(_result, _user_id, _file_id), do: :ok
end

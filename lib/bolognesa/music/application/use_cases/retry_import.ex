defmodule Bolognesa.Music.Application.UseCases.RetryImport do
  @moduledoc "Authorize explicit retry of a local music import."
  alias Bolognesa.Accounts
  alias Bolognesa.Accounts.Domain.Entities.AuthenticatedUser
  alias Bolognesa.Infrastructure.Observability.Events
  alias Bolognesa.Music.Application.Ports.Repositories.ImportRepository

  @type result :: :ok | {:error, :forbidden | :not_found | :unavailable}
  @spec call(AuthenticatedUser.t() | nil, pos_integer(), ImportRepository.adapter()) :: result()
  def call(actor, file_id, repository) do
    with :ok <- Accounts.authorize(actor, :admin),
         true <- is_integer(file_id) and file_id > 0 do
      repository.request_retry_with_result(file_id)
      |> observe(actor.id, file_id)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  defp observe({:ok, :requested}, user_id, file_id) do
    Events.emit(:music, :import, :requested, %{
      user_id: user_id,
      file_id: file_id,
      operation: :retry
    })

    :ok
  end

  defp observe({:ok, :unchanged}, _user_id, _file_id), do: :ok

  defp observe({:error, :unavailable} = error, user_id, file_id) do
    Events.emit(:music, :import, :retryable, %{
      user_id: user_id,
      file_id: file_id,
      reason: :storage_unavailable,
      failure_stage: :retry
    })

    error
  end

  defp observe(error, _user_id, _file_id), do: error
end

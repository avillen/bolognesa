defmodule Bolognesa.Accounts.Application.UseCases.EndSession do
  @moduledoc "Revoke the current token only."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Domain.Entities.Session
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.SessionToken
  alias Bolognesa.Infrastructure.Observability.Events

  @spec call(Session.token() | nil, UserRepository.adapter()) :: :ok | {:error, :unavailable}
  def call(token, repository) do
    case SessionToken.decode(token) do
      {:ok, raw} -> revoke(repository.delete_session(:crypto.hash(:sha256, raw)))
      {:error, :unauthenticated} -> :ok
    end
  end

  defp revoke({:ok, :deleted}) do
    Events.emit(:accounts, :session, :completed, %{operation: :revoke, result: :deleted})
    :ok
  end

  defp revoke({:ok, :not_found}), do: :ok

  defp revoke({:error, :unavailable} = error) do
    Events.emit(:accounts, :session, :failed, %{operation: :revoke, reason: :storage_unavailable})
    error
  end
end

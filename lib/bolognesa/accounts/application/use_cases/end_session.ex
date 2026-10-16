defmodule Bolognesa.Accounts.Application.UseCases.EndSession do
  @moduledoc "Revoke the current token only."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Domain.Entities.Session
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.SessionToken

  @spec call(Session.token() | nil, UserRepository.adapter()) :: :ok | {:error, :unavailable}
  def call(token, repository) do
    case SessionToken.decode(token) do
      {:ok, raw} -> repository.delete_session(:crypto.hash(:sha256, raw))
      {:error, :unauthenticated} -> :ok
    end
  end
end

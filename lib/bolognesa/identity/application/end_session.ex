defmodule Bolognesa.Identity.Application.EndSession do
  @moduledoc "Revoke the current token only."
  alias Bolognesa.Identity.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Identity.Domain.Session
  alias Bolognesa.Identity.Domain.SessionToken

  @spec call(Session.token() | nil, UserRepository.adapter()) :: :ok | {:error, :unavailable}
  def call(token, repository) do
    case SessionToken.decode(token) do
      {:ok, raw} -> repository.delete_session(:crypto.hash(:sha256, raw))
      {:error, :unauthenticated} -> :ok
    end
  end
end

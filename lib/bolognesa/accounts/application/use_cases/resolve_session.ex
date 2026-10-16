defmodule Bolognesa.Accounts.Application.UseCases.ResolveSession do
  @moduledoc "Resolve a cookie token against an active database session."
  alias Bolognesa.Accounts.Application.Ports.Repositories.UserRepository
  alias Bolognesa.Accounts.Domain.Entities.Actor
  alias Bolognesa.Accounts.Domain.Entities.Session
  alias Bolognesa.Accounts.Domain.ValueObjects.Sessions.SessionToken

  @spec call(Session.token() | nil, UserRepository.adapter()) ::
          {:ok, Actor.t()} | {:error, :unauthenticated | :unavailable}
  def call(token, repository) do
    with {:ok, raw} <- SessionToken.decode(token),
         {:ok, user} <- find_active_user(raw, repository) do
      {:ok, Actor.from_user(user)}
    end
  end

  defp find_active_user(raw, repository) do
    case repository.find_active_session(:crypto.hash(:sha256, raw), DateTime.utc_now()) do
      {:ok, user} -> {:ok, user}
      :not_found -> {:error, :unauthenticated}
      {:error, :unavailable} = error -> error
    end
  end
end

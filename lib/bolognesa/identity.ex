defmodule Bolognesa.Identity do
  @moduledoc "Public identity and access facade."
  alias Bolognesa.Identity.Application.{EndSession, InstallAdmin, ResolveSession, StartSession}
  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identity.Infrastructure.BcryptHasher
  alias Bolognesa.Identity.Infrastructure.Persistence.EctoRepository

  def setup_status do
    case EctoRepository.admin_exists?() do
      {:ok, true} -> {:ok, :closed}
      {:ok, false} -> {:ok, :open}
      {:error, :unavailable} = error -> error
    end
  end

  def install_admin(attrs) do
    with {:ok, user} <- InstallAdmin.call(attrs, EctoRepository, BcryptHasher) do
      {:ok, Actor.from_user(user)}
    end
  end

  def authorize(%Actor{role: :admin}, :admin), do: :ok
  def authorize(_, :admin), do: {:error, :forbidden}

  def start_session(email, password),
    do: StartSession.call(email, password, EctoRepository, BcryptHasher)

  def fetch_actor(token), do: ResolveSession.call(token, EctoRepository)
  def end_session(token), do: EndSession.call(token, EctoRepository)
end

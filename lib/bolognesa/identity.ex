defmodule Bolognesa.Identity do
  @moduledoc "Public identity and access facade."
  alias Bolognesa.Identity.Application.UseCases.{
    EndSession,
    InstallAdmin,
    ResolveSession,
    StartSession
  }

  alias Bolognesa.Identity.Domain.Actor
  alias Bolognesa.Identity.Domain.NewAdmin
  alias Bolognesa.Identity.Domain.Session
  alias Bolognesa.Identity.Domain.User
  alias Bolognesa.Identity.Infrastructure.Repositories.EctoUserRepository
  alias Bolognesa.Identity.Infrastructure.Services.BcryptHasher

  @spec setup_status() :: {:ok, :open | :closed} | {:error, :unavailable}
  def setup_status do
    case EctoUserRepository.admin_exists?() do
      {:ok, true} -> {:ok, :closed}
      {:ok, false} -> {:ok, :open}
      {:error, :unavailable} = error -> error
    end
  end

  @spec install_admin(NewAdmin.attrs()) ::
          {:ok, Actor.t()}
          | {:error, {:invalid, NewAdmin.validation_errors()} | :setup_closed | :unavailable}
  def install_admin(attrs) do
    with {:ok, user} <- InstallAdmin.call(attrs, EctoUserRepository, BcryptHasher) do
      {:ok, Actor.from_user(user)}
    end
  end

  @spec authorize(Actor.t() | nil, :admin) :: :ok | {:error, :forbidden}
  def authorize(%Actor{role: :admin}, :admin), do: :ok
  def authorize(_, :admin), do: {:error, :forbidden}

  @spec start_session(User.email(), User.password()) ::
          {:ok, Session.token()} | {:error, :invalid_credentials | :unavailable}
  def start_session(email, password),
    do: StartSession.call(email, password, EctoUserRepository, BcryptHasher)

  @spec fetch_actor(Session.token() | nil) ::
          {:ok, Actor.t()} | {:error, :unauthenticated | :unavailable}
  def fetch_actor(token), do: ResolveSession.call(token, EctoUserRepository)

  @spec end_session(Session.token() | nil) :: :ok | {:error, :unavailable}
  def end_session(token), do: EndSession.call(token, EctoUserRepository)
end
